<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Triggers and Scheduled Actions

AshOban provides two primitives which, combined, should handle most use cases.
Keep in mind, however, that you still have all of Oban at your disposal and, should the need arise, you can define "standard" oban jobs to do whatever you need to do.

> ### Cron Syntax {: .info}
> You'll see cron syntax used throughout this guide. "@daily" is a shorthand for "0 0 * * *". See [cron syntax](https://crontab.guru/) for more examples.

### Triggers

A trigger describes an action that is run periodically for records that match a condition.
It can also be used to trigger an action to happen "once in the background", but this "run later"
pattern can often be a design issue.

For example, lets say we want to send a notification to a user when their subscription is about to expire.
We *could* write a function like this, and run it once a day:

```elixir
def send_subscription_expiration_notification(user) do
  Subscription
  |> Ash.Query.for_read(:subscriptions_about_to_expire)
  |> Ash.stream!()
  |> Enum.each(&send_expiring_subscription_email/1)
end
```

What are the problems with this approach?

1. The entire operation fails or succeeds as one, and you aren't necessarily sure *which* succeeded. So you can't just retry the failed ones.
2. If you want to resend one of these notifications, you have to do it manually by executing some code (i.e fetching a given user and calling `send_expiring_subscription_email/1`).
3. There is no state in your application that indicates whether or not this action has been performed for a given user.

Lets look at how it could be done using `AshOban` triggers.

First, we add an action with a change that contains the logic to send the email. (See the Ash docs for more on changes).

```elixir
# on `Subscription`
#
# now we have a well defined action that expresses this logic
update :send_subscription_expiration_notification do
  change SendExpiringSubscriptionEmail
end
```

Next we use some application state to indicate when the last time we notified them of their subscription expiration was:

```elixir
attributes do
  attribute :last_subscription_expiration_notification_sent_at, :utc_datetime_usec
  ...
end
```

And we also add some calculations to determine if the user should get one of these emails:

```elixir
calculations do
  calculate :subscription_expires_soon, :boolean do
    calculation expr(
      expires_at < from_now(30, :day)
    )
  end

  calculate :should_send_expiring_subscription_email, :boolean do
    calculation expr(
      subscription_expires_soon and
      (is_nil(last_subscription_expiration_notification_sent_at) ||
        last_subscription_expiration_notification_sent_at < ago(30, :day))
    )
  end
end
```

Next, we add a trigger that checks for and runs these actions periodically.

```elixir
oban do
  triggers do
    trigger :send_subscription_expiration_notification do
      # Defaults to an aggressive every one minute currently
      # This default will change in the future major version release
      scheduler_cron "@daily"
      action :send_subscription_expiration_notification
      where expr(should_send_expiring_subscription_email)
      read_action :read
      worker_module_name __MODULE__.Process.Worker
      scheduler_module_name __MODULE__.Process.Scheduler
    end
  end
end
```

Now, instead of relying on a "background job" to be the authoritative source of truth, we have everything modeled as a part of our domain model.
For example, we can see without sending the emails, how many users have subscriptions expiring soon, and how many should get an email. If something
goes wrong with the job on the first day (maybe our email provider is unavailable), those users will get an email the next day. Each individual
call to `send_subscription_expiration_notification` gets its own oban job, meaning that if one fails, the others are unaffected. If someone says
"Hey, I never got my email", you can look at their subscription state to see why, and potentially retrigger it by setting `last_subscription_expiration_notification_sent_at` to `nil`.

### Chunk Processing (Oban Pro)

By default, each matching record gets its own Oban job. This is safe and simple, but can be inefficient at scale — if 10,000 records match a trigger, that means 10,000 individual `Ash.update/2` calls, each with its own database round-trip and Oban overhead.

If you have [Oban Pro](https://getoban.pro), you can use **chunk processing** to batch records together. With chunks configured, the scheduler still creates one job per record, but Oban's `ChunkWorker` collects them into batches and delivers the batch to a single `Ash.bulk_update/4` or `Ash.bulk_destroy/4` call.

```elixir
trigger :process do
  action :process
  where expr(processed != true)
  read_action :read

  chunks do
    size 100      # collect up to 100 jobs per batch
    timeout 5_000 # wait up to 5 seconds for the batch to fill before processing
  end
end
```

#### How it works

1. The scheduler runs as usual, inserting one Oban job per matching record.
2. Oban's `ChunkWorker` accumulates jobs until either `size` is reached or `timeout` milliseconds have elapsed.
3. The collected batch is delivered to a single bulk operation — one `Ash.bulk_update!/4` or `Ash.bulk_destroy!/4` call covering all records in the batch.

#### Partitioning

Batches are automatically partitioned by `:actor` (and `:tenant` for multitenant resources), so every record in a batch shares the same actor and tenant context. You can add further partitioning with the `by` option:

```elixir
chunks do
  size 50
  by [:shard_id]  # also partition by shard_id, supplied via extra_args
end
```

#### Concurrency and rate limits

A chunk counts as **one** job execution against Oban's queue concurrency and rate limits, regardless of how many records it contains. A queue configured with `triggered_process: 10` will run at most 10 concurrent chunk batches — not 10 individual records. This makes chunk processing well-suited for high-throughput scenarios: you get the throughput of processing hundreds of records while consuming only a single concurrency slot per batch.

#### Limitations

- Requires Oban Pro (`config :ash_oban, pro?: true`).
- Only works with `update` and `destroy` actions (not generic or create actions).
- Atomic actions are recommended for efficient bulk execution, though non-atomic actions are supported via the `:stream` strategy.

### Tagging Jobs

You can attach tags to jobs for filtering and grouping in telemetry, notifications, and the Oban dashboard:

```elixir
trigger :process do
  action :process
  where expr(processed != true)
  tags ["processing", "intense"]
end

schedule :import_from_github, "0 */6 * * *" do
  action :import_from_github
  tags ["import", "external"]
end
```

Tags set via `tags` are merged with any tags you also set in `worker_opts`, so both lists are combined.

### Accessing the Oban Job

The underlying `%Oban.Job{}` struct is available in the context of any action run by a trigger or scheduled action. Access it via `context.ash_oban.job`:

```elixir
# In a change module
def change(changeset, _opts, context) do
  job = context.ash_oban.job
  Ash.Changeset.put_context(changeset, :oban_tags, job.tags)
end

# In a generic action implementation
def run(input, _opts, context) do
  job = context.ash_oban.job
  Logger.info("Attempt #{job.attempt} of #{job.max_attempts}")
  :ok
end
```

> ### Chunk processing {: .info}
> The `oban_job` is not available in chunk worker contexts, since those process a batch of jobs rather than a single one.

### Controlling Job Behavior (Snooze and Cancel)

From within any action run by a trigger or scheduled action, you can snooze or cancel the Oban job by raising (or returning as an error) `AshOban.Errors.SnoozeJob` or `AshOban.Errors.CancelJob`. These work from both the main action and the `on_error` action.

#### Snoozing a job

Snoozing re-schedules the job to run again after a delay without consuming an attempt. Use this for transient conditions like rate limits or temporary unavailability:

```elixir
update :sync_with_external_api do
  change fn changeset, _context ->
    case ExternalAPI.rate_limit_remaining() do
      0 ->
        Ash.Changeset.add_error(
          changeset,
          AshOban.Errors.SnoozeJob.exception(snooze_for: 60)
        )
      _ ->
        do_sync(changeset)
    end
  end
end
```

Or via `raise`:

```elixir
raise AshOban.Errors.SnoozeJob, snooze_for: 60
```

The `snooze_for` field is an integer number of seconds.

#### Cancelling a job

Cancelling stops all retries and marks the job as cancelled. Use this when you determine that further processing is permanently invalid:

```elixir
update :process do
  change fn changeset, _context ->
    record = changeset.data

    if record.deleted_at do
      Ash.Changeset.add_error(
        changeset,
        AshOban.Errors.CancelJob.exception(reason: :record_deleted)
      )
    else
      do_process(changeset)
    end
  end
end
```

Or via `raise`:

```elixir
raise AshOban.Errors.CancelJob, reason: :permanently_invalid
```

The `reason` field accepts any term.

#### From the on_error action

Both errors also work from the `on_error` action. For example, to cancel the job from your error handler rather than failing it:

```elixir
update :handle_failure do
  change fn changeset, _context ->
    # Log the failure, then cancel the job instead of failing it
    Ash.Changeset.add_error(
      changeset,
      AshOban.Errors.CancelJob.exception(reason: :handled)
    )
  end
end
```

### Scheduled Actions

Scheduled actions are a much simpler concept than triggers. They are used to perform a generic action on a specified schedule. For example, lets say
you want to trigger an import from an external service every 6 hours.

```elixir
action :import_from_github do
  run fn _input, _ ->
    # import logic here
  end
end
```

Then you could schedule it to run every 6 hours:

```elixir
schedule :import_from_github, "0 */6 * * *" do
  worker_module_name AshOban.Test.Triggered.AshOban.ActionWorker.SayHello
end
```
