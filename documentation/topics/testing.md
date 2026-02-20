# Testing

AshOban provides the `AshOban.Test` module for testing triggers and scheduled actions. The core idea is simple: schedule and drain Oban queues synchronously in your test so you can assert on the side effects.

## Configuration

Set Oban to manual testing mode in your test config. This prevents jobs from running automatically and lets you control execution in tests.

```elixir
# config/test.exs
config :my_app, Oban, testing: :manual
```

Make sure the queues used by your triggers are listed in your Oban config (in any environment config or your runtime config). The default queue name for a trigger is the resource's short name joined with the trigger name, e.g. a `:process` trigger on `MyApp.Invoice` uses the queue `:invoice_process`.

## Basic Usage

The primary testing function is `AshOban.Test.schedule_and_run_triggers/2`. It schedules trigger jobs and drains the queues synchronously, returning a map of job outcomes.

```elixir
test "unprocessed records get processed" do
  record =
    MyApp.Invoice
    |> Ash.Changeset.for_create(:create, %{status: :pending})
    |> Ash.create!()

  assert %{success: 2} =
    AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :process})

  assert Ash.reload!(record).status == :processed
end
```

The `success: 2` count above reflects two successful jobs: one for the **scheduler** (which finds matching records and enqueues worker jobs) and one for the **worker** (which runs the action on the record).

## What to Pass

You can pass various things to `schedule_and_run_triggers/2`:

```elixir
# A specific trigger on a resource (most common in tests)
AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :send_reminder})

# All triggers on a resource
AshOban.Test.schedule_and_run_triggers(MyApp.Invoice)

# All triggers across a domain
AshOban.Test.schedule_and_run_triggers(MyApp.Billing)

# All triggers for an OTP app
AshOban.Test.schedule_and_run_triggers(:my_app)

# A list of any of the above
AshOban.Test.schedule_and_run_triggers([MyApp.Invoice, {MyApp.Order, :fulfill}])
```

Targeting a specific `{resource, trigger_name}` tuple is recommended in tests for clarity and to avoid running unrelated triggers.

## Testing Scheduled Actions

Scheduled actions are **not** included by default. Pass `scheduled_actions?: true` to include them:

```elixir
AshOban.Test.schedule_and_run_triggers(MyApp.Report, scheduled_actions?: true)
```

Or target one by name with a tuple (this automatically includes it):

```elixir
AshOban.Test.schedule_and_run_triggers({MyApp.Report, :generate_daily_summary})
```

## Asserting Results

The return value is a map you can pattern match on:

```elixir
assert %{success: 3, failure: 0} =
  AshOban.Test.schedule_and_run_triggers(MyApp.Invoice)

# Assert that a job was discarded (e.g. max attempts exceeded)
assert %{discard: 1, success: 1} =
  AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :fail_example})
```

The keys in the result map are:

| Key | Meaning |
|---|---|
| `success` | Jobs that completed successfully |
| `failure` | Jobs that raised an error and will be retried |
| `discard` | Jobs that exceeded max attempts and were discarded |
| `cancelled` | Jobs that were cancelled |
| `snoozed` | Jobs that were snoozed for later |
| `queues_not_drained` | Queues that were not drained (when `drain_queues?: false`) |

## Testing with Actors

If your triggers run authorized actions, you can pass an actor. This requires an [actor persister](/documentation/tutorials/getting-started-with-ash-oban.md#persisting-the-actor-along-with-a-job) to be configured.

```elixir
AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :process},
  actor: %MyApp.Accounts.User{id: 1}
)
```

## Testing with Multitenancy

No special configuration is needed. If your triggers are tenant-aware (using `list_tenants` or `use_tenant_from_record?`), they will automatically scope to the correct tenant during testing just as they do in production.

## Typical Test Structure

A full test typically follows this pattern:

1. **Arrange** - Create the records and conditions that should match your trigger's `where` filter
2. **Act** - Call `AshOban.Test.schedule_and_run_triggers/2`
3. **Assert** - Check that the expected side effects occurred

```elixir
defmodule MyApp.Invoice.SendReminderTest do
  use MyApp.DataCase, async: true

  test "sends reminder for unpaid invoices older than 7 days" do
    # Arrange: create an old unpaid invoice
    invoice = create_invoice(status: :unpaid, inserted_days_ago: 10)

    # Act: run the trigger
    AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :send_reminder})

    # Assert: check the side effect
    assert_email_sent_to(invoice.customer_email)
  end

  test "does not send reminder for recent invoices" do
    # Arrange: create a recent unpaid invoice
    _invoice = create_invoice(status: :unpaid, inserted_days_ago: 1)

    # Act
    AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :send_reminder})

    # Assert: no email sent
    refute_any_email_sent()
  end

  test "does not send reminder for paid invoices" do
    # Arrange
    _invoice = create_invoice(status: :paid, inserted_days_ago: 10)

    # Act
    AshOban.Test.schedule_and_run_triggers({MyApp.Invoice, :send_reminder})

    # Assert
    refute_any_email_sent()
  end
end
```

## Lower-Level Testing

For more granular control, you can use `Oban.Testing` directly alongside AshOban's scheduling functions.

### Inspecting Enqueued Jobs

```elixir
use Oban.Testing, repo: MyApp.Repo

test "extra args are set on trigger jobs" do
  invoice = create_invoice(status: :unpaid)

  # Schedule without draining
  AshOban.schedule(MyApp.Invoice, :process)

  # Inspect the scheduler job
  assert [_scheduler] =
    all_enqueued(worker: MyApp.Invoice.AshOban.Scheduler.Process)

  # Drain the scheduler queue to create worker jobs
  Oban.drain_queue(queue: :invoice_process)

  # Inspect the worker job
  assert [job] =
    all_enqueued(worker: MyApp.Invoice.AshOban.Worker.Process)

  assert job.args["primary_key"]["id"] == invoice.id
end
```

### Running a Trigger for a Specific Record

Use `AshOban.run_trigger/3` to enqueue a job for a specific record without going through the scheduler:

```elixir
record = create_invoice(status: :unpaid)

AshOban.run_trigger(record, :process,
  action_arguments: %{notify: true},
  actor: %MyApp.User{id: 1}
)

# Then drain queues to execute it
AshOban.Test.schedule_and_run_triggers(MyApp.Invoice)
```
