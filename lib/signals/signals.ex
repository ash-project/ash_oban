# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Signals do
  @schema [
    queue: [
      type: :atom,
      default: :default,
      doc: "The queue to insert jobs into."
    ],
    priority: [
      type: {:in, 0..9},
      default: 0,
      doc: "The priority of the jobs, from 0 (highest) to 9 (lowest)."
    ],
    max_attempts: [
      type: :pos_integer,
      default: 20,
      doc: "How many times a job is attempted before it is discarded."
    ],
    tags: [
      type: {:list, :string},
      default: [],
      doc: "Tags added to the jobs."
    ],
    unique: [
      type:
        {:or,
         [
           {:literal, false},
           {:keyword_list,
            [
              keys: [
                type: {:list, :atom},
                default: [:signal_id],
                doc: "The signal fields that make a job unique."
              ],
              period: [
                type: :any,
                default: :infinity,
                doc: "How long a job stays unique, as Oban's `:period`."
              ],
              states: [
                type: :any,
                default: :incomplete,
                doc: "The states in which a job stays unique, as Oban's `:states`."
              ]
            ]}
         ]},
      doc: """
      Prevents inserting a job for the listener while another one for the same values of the
      given signal fields exists. By default, jobs are unique by `signal_id`, so emitting the same
      signal again doesn't insert a second job while the first one is incomplete. `false` turns
      uniqueness off.
      """
    ],
    chunks: [
      type:
        {:keyword_list,
         [
           size: [
             type: :pos_integer,
             default: 100,
             doc: "The most signals to run the listener with at once."
           ],
           timeout: [
             type: :pos_integer,
             default: 1000,
             doc: "How long to wait, in milliseconds, for a chunk to fill before running it."
           ]
         ]},
      doc: """
      Runs the listener with many signals at once, using an Oban Pro chunk worker. Create, update
      and destroy listeners handle a chunk's signals with one bulk action, and generic actions
      with `batch?: true` receive them as a list. Requires Oban Pro, and the `AshOban` extension
      on the listener's resource, which defines the worker.
      """
    ],
    upgrader: [
      type: {:spark_behaviour, AshOban.Signals.Upgrader},
      doc:
        "Upgrades signals stored by an older version of the signal. See `AshOban.Signals.Upgrader`."
    ],
    actor_persister: [
      type: {:or, [{:literal, :none}, :atom]},
      doc: """
      The `AshOban.ActorPersister` used to store the actor in jobs. Defaults to
      `config :ash_oban, :actor_persister`. Without one, the listener runs without an actor.
      """
    ],
    shared_context: [
      type: {:or, [{:literal, :all}, {:list, {:in, [:ash_oban?, :job]}}]},
      doc:
        "Context passed to the listener's action as shared context. See `AshOban.build_context/2`."
    ]
  ]

  @moduledoc """
  An `Ash.Signals.Delivery` that runs a listener in Oban jobs.

  ```elixir
  signals_in do
    from MyApp.Shop.Signals do
      on :order_placed, :send_receipt, delivery: {AshOban.Signals, queue: :mailers}
    end
  end
  ```

  When the signal is emitted, a job is inserted for each signal. The job runs the listener the
  way the inline delivery would have, with the actor, tenant and `authorize?` of the emitting
  action. If the listener fails, the job is retried. With `chunks`, jobs are run together, and the
  listener runs once for each chunk, with every signal in it.

  Jobs are inserted with Oban's repo. When the emitting action uses the same repo and the
  signal is emitted `:after_action`, the jobs are inserted in the action's transaction, so they
  are only committed with the action's changes, and the listener runs after they are committed.

  See the [Signals guide](signals.html) for more.

  ### Changing signals

  A job stores its signal as it was when it was emitted, and may run after a deploy has changed
  the signal. Before it runs, the stored signal is loaded with the signal's current definition:

  - a field the signal no longer has is ignored;
  - a field the stored signal doesn't have is `nil`, or its default;
  - a required field the stored signal doesn't have, or a value the field's type can no longer
    load, fails the job.

  So adding an optional field, or removing one, is safe. Renaming a field, adding a required one,
  or changing a field's type is not: to make a change like that, either give the listener an
  `upgrader`, which changes stored signals before they are loaded, or add a new signal for the
  new shape and emit both until the old signal's jobs have run. A job that fails to load is
  retried like any other, which leaves time to deploy an upgrader.

  The same applies to listeners. A job for a listener that no longer exists, or that now
  listens to a different signal, fails, and is retried until it is discarded. Before removing or
  renaming a listener, or the signal it listens to, wait for its jobs to finish. During a
  rolling deploy, a job inserted by a new node may be picked up by an old one, fail, and run
  when it is retried on a new node.

  ### Options

  #{Spark.Options.docs(@schema)}
  """

  @behaviour Ash.Signals.Delivery

  @impl true
  def deliver(signals, listeners, opts, context) do
    opts = options!(opts)

    with {:ok, stored} <- Ash.Signals.dump(context.signal_module, context.signal.name, signals) do
      listeners
      |> Enum.flat_map(fn listener -> Enum.map(stored, &job(listener, &1, opts, context)) end)
      |> insert()
    end
  end

  @impl true
  def verify_listener(_listener, signal, opts, dsl_state) do
    with {:ok, opts} <- validate(opts),
         :ok <- verify_unique(signal, opts) do
      verify_chunks(opts, dsl_state)
    end
  end

  defp verify_unique(signal, opts) do
    fields = [:signal_id | Enum.map(signal.arguments, & &1.name)]
    keys = if unique = unique(opts), do: unique[:keys], else: []

    case Enum.reject(keys, &(&1 in fields)) do
      [] ->
        :ok

      unknown ->
        {:error,
         "`unique` refers to #{Enum.map_join(unknown, ", ", &"`#{inspect(&1)}`")}, which #{if match?([_], unknown), do: "is not a field", else: "are not fields"} of the signal."}
    end
  end

  defp verify_chunks(opts, dsl_state) do
    cond do
      !opts[:chunks] ->
        :ok

      !AshOban.Info.pro?() ->
        {:error, "`chunks` requires Oban Pro. Set `config :ash_oban, pro?: true`."}

      AshOban not in Spark.Dsl.Verifier.get_persisted(dsl_state, :extensions, []) ->
        {:error,
         "`chunks` requires the `AshOban` extension on the resource, which defines the listener's chunk worker."}

      true ->
        :ok
    end
  end

  @doc false
  def options!(opts), do: Spark.Options.validate!(opts, @schema)

  @doc false
  def validate(opts) do
    case Spark.Options.validate(opts, @schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc false
  # The chunk worker that the `AshOban` extension defines for a listener with `chunks`.
  def chunk_worker(resource, listener_name) do
    Module.concat([resource, AshOban.SignalWorker, Macro.camelize(to_string(listener_name))])
  end

  # `false`, or the keys, period and states that make a job unique.
  defp unique(opts) do
    case Keyword.get(opts, :unique) do
      nil -> [keys: [:signal_id], period: :infinity, states: :incomplete]
      unique -> unique
    end
  end

  defp job(listener, stored, opts, context) do
    unique = unique(opts)

    worker =
      if opts[:chunks],
        do: chunk_worker(listener.resource, listener.name),
        else: AshOban.Signals.Worker

    %{
      "signal_module" => Atom.to_string(listener.signal_module),
      "signal" => Atom.to_string(listener.signal),
      "resource" => Atom.to_string(listener.resource),
      "listener" => Atom.to_string(listener.name),
      "payload" => stored,
      "tenant" => tenant(context.tenant, listener.resource),
      "authorize?" => context.authorize?
    }
    |> AshOban.store_actor(context.actor, opts[:actor_persister])
    |> put_unique(stored, unique)
    |> worker.new(
      queue: opts[:queue],
      priority: opts[:priority],
      max_attempts: opts[:max_attempts],
      tags: opts[:tags],
      unique: unique_opts(unique)
    )
  end

  defp tenant(nil, _resource), do: nil
  defp tenant(tenant, resource), do: Ash.ToTenant.to_tenant(tenant, resource)

  defp put_unique(args, _stored, false), do: args

  defp put_unique(args, stored, unique) do
    Map.put(
      args,
      "unique",
      Map.new(unique[:keys], fn key ->
        {Atom.to_string(key), Map.get(stored, key, Map.get(stored, Atom.to_string(key)))}
      end)
    )
  end

  defp unique_opts(false), do: false

  defp unique_opts(unique) do
    [
      keys: [:signal_module, :signal, :resource, :listener, :unique],
      period: unique[:period],
      states: unique[:states]
    ]
  end

  # Only Oban Pro's engine enforces uniqueness in `insert_all`.
  defp insert(jobs) do
    if Oban.config().engine in [Oban.Pro.Engines.Smart, Oban.Pro.Engine] do
      Oban.insert_all(jobs)
      :ok
    else
      Enum.reduce_while(jobs, :ok, fn job, :ok ->
        case Oban.insert(job) do
          {:ok, _job} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end
end
