# Get Started With Ash Oban

AshOban will likely grow to provide many more oban-related features, but for now the primary focus is on "triggers".

A trigger describes an action that is run periodically.

This guide will need to be expanded, this is primarily a placeholder with an example.

## Setup

First, follow the oban setup guide.

If you are using Oban Pro, set the following configuration:

```elixir
config :ash_oban, :pro?, true
```

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

    # add a triggere called `:process`
    trigger :process do
      # this trigger calls the `process` action
      action :process
      # for any record that has `processed != true`
      where expr(processed != true)
      # checking for matches every minute     
      scheduler_cron "* * * * *"
    end
  end
end
```

See the DSL documentation for more: `AshOban`

## Changing Triggers

To remove or disable triggers, *do not just remove them from your resource*. Due to the way that oban implements cron jobs, if you just remove them from your resource, the cron will attempt to continue scheduling jobs. Instead, set `paused true` or `delete true` on the trigger. See the oban docs for more: https://getoban.pro/docs/pro/0.14.1/Oban.Pro.Plugins.DynamicCron.html#module-using-and-configuring


