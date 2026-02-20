# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test do
  @moduledoc """
  Helpers for testing AshOban triggers and scheduled actions.

  This module provides a convenient wrapper around `AshOban.schedule_and_run_triggers/2`
  that defaults to draining queues, which is the typical behavior you want in tests.

  ## Setup

  Before using this module, ensure your Oban config uses `testing: :manual`:

      # config/test.exs
      config :my_app, Oban, testing: :manual

  See the [Testing Guide](/documentation/topics/testing.md) for full setup instructions.

  ## Basic Usage

      # Run all triggers for a resource
      AshOban.Test.schedule_and_run_triggers(MyApp.MyResource)

      # Run a specific trigger
      AshOban.Test.schedule_and_run_triggers({MyApp.MyResource, :process})

      # Run all triggers for a domain
      AshOban.Test.schedule_and_run_triggers(MyApp.MyDomain)

      # Run all triggers for an OTP app
      AshOban.Test.schedule_and_run_triggers(:my_app)

      # Include scheduled actions (excluded by default)
      AshOban.Test.schedule_and_run_triggers(MyApp.MyResource, scheduled_actions?: true)

  ## Asserting Results

  The function returns a map of job outcomes that you can pattern match on:

      assert %{success: 2} =
        AshOban.Test.schedule_and_run_triggers({MyApp.MyResource, :process})

      assert %{success: 1, failure: 0} =
        AshOban.Test.schedule_and_run_triggers(MyApp.MyResource)
  """

  @doc """
  Schedules and runs triggers, draining queues by default.

  This is a wrapper around `AshOban.schedule_and_run_triggers/2` with `drain_queues?: true`
  set by default, making it suitable for use in tests where you want jobs to execute
  synchronously.

  ## Arguments

  * `resources_or_domains_or_otp_apps` - Can be any of the following:
    * A resource module - runs all triggers for that resource
    * A `{resource, :trigger_name}` tuple - runs a specific trigger
    * A domain module - runs all triggers for all resources in that domain
    * An OTP app atom - runs all triggers for all domains in that app
    * A list of any of the above

  ## Options

  * `:drain_queues?` - Whether to drain queues after scheduling. Defaults to `true`
    (unlike `AshOban.schedule_and_run_triggers/2` which defaults to `false`).
  * `:scheduled_actions?` - Whether to include scheduled actions. Defaults to `false`.
    When passing a `{resource, :scheduled_action_name}` tuple this is automatically enabled.
  * `:triggers?` - Whether to include triggers. Defaults to `true`.
  * `:actor` - The actor to pass to the trigger actions. Requires an actor persister to be configured.
  * `:oban` - The Oban instance to use. Defaults to `Oban`.
  * `:queue` - Passed through to `Oban.drain_queue/2`.
  * `:with_limit` - Passed through to `Oban.drain_queue/2`.
  * `:with_recursion` - Passed through to `Oban.drain_queue/2`.
  * `:with_safety` - Passed through to `Oban.drain_queue/2`.
  * `:with_scheduled` - Passed through to `Oban.drain_queue/2`.

  ## Return Value

  Returns a map with job outcome counts:

      %{
        success: non_neg_integer(),
        failure: non_neg_integer(),
        discard: non_neg_integer(),
        cancelled: non_neg_integer(),
        snoozed: non_neg_integer(),
        queues_not_drained: [atom()]
      }

  ## Examples

      # Run all triggers for a resource and assert outcomes
      assert %{success: 3, failure: 0} =
        AshOban.Test.schedule_and_run_triggers(MyResource)

      # Run a specific trigger with an actor
      assert %{success: 2} =
        AshOban.Test.schedule_and_run_triggers({MyResource, :process},
          actor: %MyApp.User{id: 1}
        )
  """
  def schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts \\ []) do
    opts = Keyword.put_new(opts, :drain_queues?, true)
    AshOban.schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts)
  end
end
