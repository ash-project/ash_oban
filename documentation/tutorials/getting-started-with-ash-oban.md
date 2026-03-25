<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Getting Started With Ash Oban

## Get familiar with Ash resources

If you haven't already, read the [Ash Getting Started Guide](https://hexdocs.pm/ash/get-started.html), and familiarize yourself with Ash and Ash resources.

## Get familiar with AshOban Triggers & Scheduled Actions

See [Triggers and Scheduled Actions](/documentation/topics/triggers-and-scheduled-actions.md) to read
about what `AshOban` provides.

## Bring in the `ash_oban` dependency

```elixir
{:ash_oban, "~> 0.8.5"}
```

## Setup

### Oban Pro

If you are using Oban Pro, set the following configuration:

```elixir
config :ash_oban, :pro?, true
```

Oban Pro lives in a separate hex repository, and therefore we, unfortunately, cannot have an explicit version dependency on it.
What this means is that any version you use in hex will technically be accepted, and if you don't have the oban pro package installed
and you use the above configuration, you will get compile time errors/warnings.

<!-- tabs-open -->

### Using Igniter (recommended)

This will install oban as well.

```elixir
mix igniter.install ash_oban
```

### Manual

Next, allow AshOban to alter your configuration in your Application module:

```elixir
# Replace this
{Oban, your_oban_config}

# With this
{Oban, AshOban.config(Application.fetch_env!(:my_app, :ash_domains), your_oban_config)}
# OR this, to selectively enable AshOban only for specific domains
{Oban, AshOban.config([YourDomain, YourOtherDomain], your_oban_config)}
```

<!-- tabs-close -->

## Usage

> #### Warning {: .warning}
> Currently, even without `scheduler_cron` specified, the triggers will run every minute. To disable this behavior, add `scheduler_cron false`. This will change with the next major release.

Finally, configure your triggers in your resources.

Add the `AshOban` extension and define a trigger.

For example:

```elixir
defmodule MyApp.Resource do
  use Ash.Resource, domain: MyDomain, extensions: [AshOban]

  ...

  oban do
    triggers do
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
end
```

Make sure to add the queue to the list of queues in Oban configuration.
Default queue is resources short name plus the name of the trigger. 
For the above example you would add `:resource_process` queue to Oban queues in config.
Alternatively, you can define your own queue in the trigger.

See the DSL documentation for more: [`AshOban`](/documentation/dsl/DSL-AshOban.md)

## Handling Errors

Error handling is done by adding an `on_error` to your trigger. This is an update action that will get the error as an argument called `:error`. The error will be an Ash error class. These error classes can contain many kinds of errors, so you will need to figure out handling specific errors on your own. Be sure to add the `:error` argument to the action if you want to receive the error.

This is _not_ foolproof. You want to be sure that your `on_error` action is as simple as possible, because if an exception is raised during the `on_error` action, the oban job will fail. If you are relying on your `on_error` logic to alter the resource to make it no longer apply to a trigger, consider making your action do _only that_. Then you can add another trigger watching for things in an errored state to do more rich error handling behavior.

## Triggering on action

Often you would need the trigger to activate when certain actions are performed, e.g. to expedite processing of new and updated records. 

For that you can use `AshOban.Changes.BuiltinChanges.run_oban_trigger`

For example:
```elixir
defmodule MyApp.Resource do
  use Ash.Resource, domain: MyDomain, extensions: [AshOban]

  ...

  oban do
    triggers do
      trigger :process do
        action :process
        where expr(processed != true)
      end
    end
  end

  create :create do
    accept :*
    change run_oban_trigger(:process)
  end
end
```

## Changing Triggers when using Oban Pro

To remove or disable triggers, _do not just remove them from your resource_. Due to the way that Oban Pro implements cron jobs, if you just remove them from your resource, the cron will attempt to continue scheduling jobs. Instead, set `state :paused` or `state :deleted` on the trigger. See the oban docs for more: https://getoban.pro/docs/pro/0.14.1/Oban.Pro.Plugins.DynamicCron.html#module-using-and-configuring

PS: `state :deleted` is also idempotent, so there is no issue with deploying with that flag set to true multiple times. After you have deployed once with `state :deleted` you can safely delete the trigger.

When not using Oban Pro, all crons are simply loaded on boot time and there is no side effects to simply deleting an unused trigger.

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

## Authorizing actions

As of v0.2, `authorize?: true` is passed into every action that is called. This may be a breaking change for some users that are using policies. There are two ways to get around this:

1. you can set `config :ash_oban, authorize?: false` (easiest, reverts to old behavior, but not recommended)
2. you can install the bypass at the top of your policies in any resource that you have triggers on that has policies:

```elixir
policies do
  bypass AshOban.Checks.AshObanInteraction do
    authorize_if always()
  end

  ...the rest of your policies
end
```

## Shared Context

By default, context set by AshOban (like `ash_oban?: true` and the `%Oban.Job{}` struct) is placed in the regular action context. This means it is **not** propagated to nested actions called via `manage_relationship` or other nested action invocations.

If you need AshOban context to propagate to nested actions (e.g. so that policy bypasses work in related actions), use the `shared_context` option. This places the specified keys into Ash's shared context, which is automatically propagated to all nested actions.

```elixir
# Recommended: share only the job
shared_context [:job]

# Share all AshOban context keys (ash_oban? and job)
shared_context :all
```

`shared_context` can be set at three levels, with each inheriting from the next if not specified:

1. **Per trigger or scheduled action** — set `shared_context` directly on the trigger/schedule
2. **Per resource** — set `shared_context` in the `oban` section of the resource DSL
3. **Application config** — set `config :ash_oban, shared_context: [:job]` in your app config

This makes it easy to configure shared context globally:

```elixir
# in config.exs
config :ash_oban, shared_context: [:job]
```

## Persisting the actor along with a job

Create a module that is responsible for translating the current user to a value that will be JSON encoded, and for turning that encoded value back into an actor.

```elixir
defmodule MyApp.AshObanActorPersister do
  use AshOban.ActorPersister

  def store(%MyApp.User{id: id}), do: %{"type" => "user", "id" => id}

  def lookup(%{"type" => "user", "id" => id}), do: MyApp.Accounts.get_user_by_id(id)

  # This allows you to set a default actor
  # in cases where no actor was present
  # when scheduling.
  def lookup(nil), do: {:ok, nil}
end
```

Then, configure this in application config.

```elixir
config :ash_oban, :actor_persister, MyApp.AshObanActorPersister
```

This global configuration will affect all oban triggers. You can also configure
an actor persister on individual triggers and scheduled actions, i.e

```elixir
trigger :name do
  ...
  actor_persister MyApp.AshObanActorPersister
end
```

Or you can use `:none` to override the globally configured actor persister

```elixir
trigger :name do
  ...
  actor_persister :none
end
```


### Considerations

There are a few things that are important to keep in mind:

1. The actor could be deleted or otherwise unavailable when you look it up. You very likely want your `lookup/1` to return an error in that scenario.

2. The actor can have changed between when the job was scheduled and when the trigger is executing. It can even change across retries. If you are trying to authorize access for a given trigger's update action to a given actor, keep in mind that just because the trigger is running for a given action, does _not_ mean that the conditions that allowed them to originally _schedule_ that action are still true.
