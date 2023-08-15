# Get Started With Ash Oban

AshOban will likely grow to provide many more oban-related features, but for now the primary focus is on "triggers".

A trigger describes an action that is run periodically.

## Get familiar with Ash resources

If you haven't already, read the [Ash Getting Started Guide](https://hexdocs.pm/ash/get-started.html), and familiarize yourself with Ash and Ash resources.

## Bring in the ash_oban dependency

```elixir
def deps()
  [
    ...
    {:ash_oban, "~> 0.1.5"}
  ]
end
```

## Setup

First, follow the oban setup guide.

### Oban Pro

If you are using Oban Pro, set the following configuration:

```elixir
config :ash_oban, :pro?, true
```

Oban Pro lives in a separate hex repository, and therefore we, unfortunately, cannot have an explicit version dependency on it.
What this means is that any version you use in hex will technically be accepted, and if you don't have the oban pro package installed
and you use the above configuration, you will get compile time errors/warnings.

### Setting up AshOban

Next, allow AshOban to alter your configuration

```elixir
# in your application
{Oban, AshOban.config([YourApi, YourOtherApi], your_oban_config)}
```

## Usage

Finally, configure your triggers in your resources.

Add the `AshOban` extension:

```elixir
use Ash.Resource, extensions: [AshOban]
```

For example:

```elixir
oban do
  triggers do
    api YourApi

    # add a trigger called `:process`
    trigger :process do
      # this trigger calls the `process` action
      action :process
      # for any record that has `processed != true`
      where expr(processed != true)
      # checking for matches every minute     
      scheduler_cron "* * * * *"
      on_error :errored
    end
  end
end
```

See the DSL documentation for more: `AshOban`

## Handling Errors

Error handling is done by adding an `on_error` to your trigger. This is an update action that will get the error as an argument called `:error`. The error will be an Ash error class.  These error classes can contain many kinds of errors, so you will need to figure out handling specific errors on your own.  Be sure to add the `:error` argument to the action if you want to receive the error.  

This is *not* foolproof. You want to be sure that your `on_error` action is as simple as possible, because if an exception is raised during the `on_error` action, the oban job will fail. If you are relying on your `on_error` logic to alter the resource to make it no longer apply to a trigger, consider making your action do *only that*. Then you can add another trigger watching for things in an errored state to do more rich error handling behavior.

## Changing Triggers

To remove or disable triggers, *do not just remove them from your resource*. Due to the way that oban implements cron jobs, if you just remove them from your resource, the cron will attempt to continue scheduling jobs. Instead, set `paused true` or `delete true` on the trigger. See the oban docs for more: https://getoban.pro/docs/pro/0.14.1/Oban.Pro.Plugins.DynamicCron.html#module-using-and-configuring

## Transactions

AshOban adds two new transaction reasons, as it uses explicit transactions to ensure that each triggered record is properly locked and executed in serially.

```elixir
%{
  type: :ash_oban_trigger,
  metadata: %{
    resource: Resource,
    trigger: :trigger_name,
    primary_key: %{primary_key_fields: value}
  }
}
```
and
```elixir
%{
  type: :ash_oban_trigger_error,
  metadata: %{
    resource: Resource
    trigger: :trigger_name,
    primary_key: %{primary_key_fields: value},
    error: <the error (this will be an ash error class)>
  }
}
```
