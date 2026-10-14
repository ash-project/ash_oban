<!--
SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Signals

[Signals](https://hexdocs.pm/ash/signals.html) let one resource react to what happens in another,
without either depending on the other. A resource emits a signal, like `:order_placed`, and other
resources listen to it with their own actions.

By default, a listener runs immediately, as a nested action inside the emitting action. If it
fails, the emitting action fails, and if it is slow, so is the emitting action. `AshOban.Signals`
is a signal delivery that runs a listener in Oban jobs instead, so that it runs after the emitting
action has committed, and is retried when it fails.

## When to use it

Run a listener in jobs when it:

- does slow work, or calls external services
- shouldn't be able to fail the action that emits the signal
- should be retried when it fails

Keep the default, inline delivery when a listener's changes must be committed together with the
emitting action's changes, or when its failure should fail the emitting action.

Each listener chooses its delivery, so listeners of the same signal can differ, and the emitter
doesn't change.

## Usage

Set the listener's `delivery` to `AshOban.Signals`, with its options:

```elixir
signals_in do
  from MyApp.Shop.Signals do
    # runs in the emitting action's transaction
    on :order_placed, :record_sale

    # runs in a job, after the emitting action's transaction commits
    on :order_placed, :send_receipt, delivery: {AshOban.Signals, queue: :mailers}
  end
end
```

Like the queues of triggers, the queue must be listed in your Oban config, and `AshOban.config/3`
raises if it isn't, for the listeners of the resources in the domains you give it:

```elixir
config :my_app, Oban,
  queues: [default: 10, mailers: 10]
```

When the signal is emitted, a job is inserted for each signal. The job runs the listener the way
the inline delivery would have, with the actor, tenant and `authorize?` of the emitting action. If
the listener returns an error, the job fails and is retried.

These jobs use the `AshOban.Signals.Worker` worker. Their args hold the listener's resource and
name, and the signal, so you can tell them apart in Oban Web or with `Oban.Testing`.

## Transactions

Jobs are inserted with Oban's repo. Emit the signal `:after_action`, and use the same repo for
Oban and for the emitting resource. The jobs are then inserted inside the emitting action's
transaction:

- they are committed only if the action's changes are committed
- the listener runs only after the action's changes are committed, so it can read them

If the emitting resource uses a different repo, or a data layer without transactions, the jobs are
inserted as soon as the signal is emitted. If the emitting action fails after that, its jobs still
run.

## Actors

Like triggers, signal jobs store the actor with an actor persister, configured with
`config :ash_oban, :actor_persister`, or with the `actor_persister` option. Without one, the
listener runs without an actor. See
[Persisting the actor along with a job](/documentation/tutorials/getting-started-with-ash-oban.md#persisting-the-actor-along-with-a-job).

## Uniqueness

By default, a listener's jobs are unique by `signal_id`. Emitting a signal again with the same
`signal_id`, for example from `Ash.Signals.emit/5`, doesn't insert a second job while the first one
hasn't completed.

To make jobs unique by other signal fields, give them as `keys`. For example, to have at most one
pending job for each order:

```elixir
on :order_placed, :send_receipt,
  delivery: {AshOban.Signals, queue: :mailers, unique: [keys: [:order_id]]}
```

`unique` also takes Oban's `period` and `states`, which default to `:infinity` and `:incomplete`.
Use `unique: false` to turn uniqueness off.

Without Oban Pro's Smart engine, Oban only enforces uniqueness when jobs are inserted one at a
time, so signal jobs are inserted one at a time. With the Smart engine, they are inserted
together.

## Chunks

Each signal gets its own job, so that jobs can be unique, and retried on their own. With Oban Pro,
`chunks` runs those jobs together: the listener runs once for each chunk, with every signal in it.

A create, update or destroy listener handles the signals it receives with one bulk action, so a
chunked create listener creates up to `size` records at once:

```elixir
defmodule MyApp.Analytics.Sale do
  use Ash.Resource,
    domain: MyApp.Analytics,
    extensions: [AshOban]

  signals_in do
    from MyApp.Shop.Signals do
      on :order_placed, :record_sale,
        action: :create,
        delivery: {AshOban.Signals, queue: :analytics, chunks: [size: 100, timeout: 5_000]}
    end
  end
end
```

A generic action receives one signal at a time, unless the listener sets `batch?: true`, in which
case it receives every signal in the chunk as a list.

A chunk holds up to `size` signals, and runs when it is full, or `timeout` milliseconds after its
first job is available. Jobs are only chunked together when they have the same actor, tenant and
`authorize?`. If the listener fails, every job in the chunk is retried.

The `AshOban` extension defines a chunk worker for each listener with `chunks`, like
`MyApp.Analytics.Sale.AshOban.SignalWorker.RecordSale`, so the resource must use it. Chunks also
require `config :ash_oban, pro?: true`.

## Options

```elixir
on :order_placed, :send_receipt,
  delivery:
    {AshOban.Signals,
     queue: :mailers,
     priority: 1,
     max_attempts: 10,
     tags: ["mailers"],
     unique: [keys: [:order_id]],
     upgrader: MyApp.Shop.OrderPlacedUpgrader,
     actor_persister: MyApp.AshObanActorPersister,
     shared_context: [:ash_oban?]}
```

The options are checked when the listener's resource is compiled. See `AshOban.Signals` for what
each one does.

## Changing signals

A job stores its signal as it was when it was emitted, and may run after a deploy has changed the
signal. Before it runs, the stored signal is loaded with the signal's current definition:

- a field the signal no longer has is ignored
- a field the stored signal doesn't have is `nil`, or its default
- a required field the stored signal doesn't have, or a value the field's type can no longer load,
  fails the job

So adding an optional field, or removing one, is safe. Renaming a field, adding a required one, or
changing a field's type is not. To make a change like that, either:

- give the listener an `upgrader`, which changes stored signals before they are loaded, or
- add a new signal for the new shape, and emit both until the old signal's jobs have run

A job that fails to load is retried like any other, which leaves time to deploy an upgrader.

An upgrader implements `AshOban.Signals.Upgrader`. It receives each stored signal as a map with
string keys:

```elixir
defmodule MyApp.Shop.OrderPlacedUpgrader do
  use AshOban.Signals.Upgrader

  # `customer_id` was renamed to `buyer_id`
  @impl true
  def upgrade(%{"customer_id" => customer_id} = signal, _opts) do
    {:ok, signal |> Map.delete("customer_id") |> Map.put("buyer_id", customer_id)}
  end

  def upgrade(signal, _opts), do: {:ok, signal}
end
```

```elixir
on :order_placed, :send_receipt,
  delivery: {AshOban.Signals, queue: :mailers, upgrader: MyApp.Shop.OrderPlacedUpgrader}
```

Once no job holds a signal in the old shape, the upgrader can be removed.

## Changing listeners

A job for a listener that no longer exists, or that now listens to a different signal, fails, and
is retried until it is discarded. Before removing or renaming a listener, or the signal it listens
to, wait for its jobs to finish. Changing a listener's delivery back to inline is fine: its
remaining jobs still run.

During a rolling deploy, a job inserted by a new node may be picked up by an old node that doesn't
have its listener yet. It fails there, and runs when it is retried on a new node.

## Testing

With Oban's `testing: :manual` mode, emitting a signal inserts its jobs without running them.
Assert on them with `Oban.Testing`, and run them with `Oban.drain_queue/1`:

```elixir
use AshOban.Test, repo: MyApp.Repo

test "placing an order sends a receipt" do
  order = MyApp.Shop.place_order!(customer, 100)

  assert_enqueued worker: AshOban.Signals.Worker,
                  args: %{"resource" => "Elixir.MyApp.Shop.Receipt", "listener" => "send_receipt"}

  assert %{success: 1} = Oban.drain_queue(queue: :mailers)
end
```

To test a listener with `chunks`, drain its queue one job at a time, with
`Oban.drain_queue(queue: :analytics, with_limit: 1, with_recursion: true)`, so that each chunk's
first job can gather the others.

`Ash.Signals.Test` works whatever the delivery, because signals are captured when they are
emitted, before they are delivered.
