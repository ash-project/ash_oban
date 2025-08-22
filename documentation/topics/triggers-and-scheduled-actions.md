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
