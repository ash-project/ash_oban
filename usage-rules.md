<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Rules for working with AshOban

## Understanding AshOban

AshOban is a package that integrates the Ash Framework with Oban, a robust job processing system for Elixir. It enables you to define triggers that can execute background jobs based on specific conditions in your Ash resources, as well as schedule periodic actions. AshOban is particularly useful for handling asynchronous tasks, background processing, and scheduled operations in your Ash application.

## Setting Up AshOban

To use AshOban with an Ash resource, add AshOban to the extensions list:

```elixir
use Ash.Resource,
  extensions: [AshOban]
```

## Defining Triggers

Triggers are the primary way to define background jobs in AshOban. They can be configured to run when certain conditions are met on your resources. They work
by running a scheduler job on the given cron job.

### Basic Trigger

```elixir
oban do
  triggers do
    trigger :process do
      action :process
      scheduler_cron "*/5 * * * *"
      where expr(processed != true)
      worker_read_action :read
      worker_module_name MyApp.Workers.Process
      scheduler_module_name MyApp.Schedulers.Process
    end
  end
end
```

### Trigger Configuration Options

- `action` - The action to be triggered (required)
- `where` - The filter expression to determine if something should be triggered
- `worker_read_action` - The read action to use when fetching individual records
- `read_action` - The read action to use when querying records (must support keyset pagination)
- `worker_module_name` - The module name for the generated worker (important for job stability)
- `scheduler_module_name` - The module name for the generated scheduler
- `max_attempts` - How many times to attempt the job (default: 1)
- `queue` - The queue to place the worker job in (defaults to trigger name)
- `trigger_once?` - Ensures that jobs that complete quickly aren't rescheduled (default: false)

## Scheduled Actions

Scheduled actions allow you to run periodic tasks according to a cron schedule:

```elixir
oban do
  scheduled_actions do
    schedule :daily_report, "0 8 * * *" do
      action :generate_report
      worker_module_name MyApp.Workers.DailyReport
    end
  end
end
```

### Scheduled Action Configuration Options

- `cron` - The schedule in crontab notation
- `action` - The generic or create action to call when the schedule is triggered
- `action_input` - Inputs to supply to the action when it is called
- `worker_module_name` - The module name for the generated worker
- `queue` - The queue to place the job in
- `max_attempts` - How many times to attempt the job (default: 1)

## Triggering Jobs Programmatically

You can trigger jobs programmatically using `run_oban_trigger` in your actions:

```elixir
update :process_item do
  accept [:item_id]
  change set_attribute(:processing, true)
  change run_oban_trigger(:process_data)
end
```

Or directly using the AshOban API:

```elixir
# Run a trigger for a specific record
AshOban.run_trigger(record, :process_data)

# Run a trigger for multiple records
AshOban.run_triggers(records, :process_data)

# Schedule a trigger or scheduled action
AshOban.schedule(MyApp.Resource, :process_data, actor: current_user)
```

## Working with Actors

AshOban can persist the actor that triggered a job, making it available when the job runs:

### Setting up Actor Persistence

```elixir
# Define an actor persister module
defmodule MyApp.ObanActorPersister do
  @behaviour AshOban.PersistActor

  @impl true
  def store(actor) do
    # Convert actor to a format that can be stored in JSON
    Jason.encode!(actor)
  end

  @impl true
  def lookup(actor_json) do
    # Convert the stored JSON back to an actor
    case Jason.decode(actor_json) do
      {:ok, data} -> {:ok, MyApp.Accounts.get_user!(data["id"])}
      error -> error
    end
  end
end

# Configure it
config :ash_oban, :actor_persister, MyApp.ObanActorPersister
```

### Using Actor in Triggers

```elixir
# Specify actor_persister for a specific trigger
trigger :process do
  action :process
  actor_persister MyApp.ObanActorPersister
end

# Pass the actor when triggering a job
AshOban.run_trigger(record, :process, actor: current_user)
```

## Multi-tenancy Support

AshOban supports multi-tenancy in your Ash application:

```elixir
oban do
  # Global tenant configuration
  list_tenants [1, 2, 3]  # or a function that returns tenants

  triggers do
    trigger :process do
      # Override tenants for a specific trigger
      list_tenants fn -> [2] end
      action :process
    end
  end
end
```

## Debugging and Error Handling

AshOban provides options for debugging and handling errors:

```elixir
trigger :process do
  action :process
  # Enable detailed debug logging for this trigger
  debug? true

  # Configure error handling
  log_errors? true
  log_final_error? true

  # Define an action to call after the last attempt has failed
  on_error :mark_failed
end
```

You can also enable global debug logging:

```elixir
config :ash_oban, :debug_all_triggers?, true
```

## Best Practices

1. **Always define module names** - Use explicit `worker_module_name` and `scheduler_module_name` to prevent issues when refactoring.

2. **Use meaningful trigger names** - Choose clear, descriptive names for your triggers that reflect their purpose.

3. **Handle errors gracefully** - Use the `on_error` option to define how to handle records that fail processing repeatedly.

4. **Use appropriate queues** - Organize your jobs into different queues based on priority and resource requirements.

5. **Optimize read actions** - Ensure that read actions used in triggers support keyset pagination for efficient processing.

6. **Design for idempotency** - Jobs should be designed to be safely retried without causing data inconsistencies.
