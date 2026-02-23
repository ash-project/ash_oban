# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test do
  @moduledoc """
  Helpers for testing AshOban triggers and scheduled actions.

  ## Setup

  Use this module in your test case to get all helpers at once:

      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            use AshOban.Test, repo: MyApp.Repo
          end
        end
      end

  `use AshOban.Test` accepts the same options as `use Oban.Testing` and
  delegates to it, so you get both Oban's own testing helpers and AshOban's
  helpers in a single call.

  See the [Testing Guide](/documentation/topics/testing.md) for full setup
  instructions.

  ## Helpers

  ### Running triggers

  `schedule_and_run_triggers/2` runs all matching jobs synchronously, which
  is the most common thing you need in tests:

      # Run all triggers for a resource
      AshOban.Test.schedule_and_run_triggers(MyApp.MyResource)

      # Run a specific trigger
      AshOban.Test.schedule_and_run_triggers({MyApp.MyResource, :process})

      assert %{success: 1, failure: 0} =
        AshOban.Test.schedule_and_run_triggers(MyApp.MyResource)

  ### Asserting enqueued jobs

  After an action that calls `run_oban_trigger`, use `assert_triggered/3` to
  verify the job was enqueued for the right record:

      {:ok, appointment} = Appointment.update(appointment, params)
      assert_triggered(appointment, :create_zoom_meeting)

  These are **macros** that require `all_enqueued/1` to be in scope (provided
  by `use AshOban.Test` or `use Oban.Testing` directly).

  ### Asserting scheduler eligibility

  Use `assert_would_schedule/3` and `refute_would_schedule/3` to check whether
  a record's current state matches a trigger's `where` filter without running
  the scheduler:

      record = MyApp.create_record!()
      assert_would_schedule(record, :process)

      processed = MyApp.process!(record)
      refute_would_schedule(processed, :process)
  """

  @doc """
  Sets up AshOban test helpers.

  Delegates to `use Oban.Testing` so Oban's own helpers (`all_enqueued`,
  `assert_enqueued`, etc.) are also available. Accepts the same options.

  ## Options

  * `:repo` - Required. The Ecto repo to use for querying Oban jobs.
  * `:prefix` - The database prefix for Oban tables. Defaults to `"public"`.

  ## Example

      use AshOban.Test, repo: MyApp.Repo, prefix: "private"
  """
  defmacro __using__(opts) do
    quote do
      use Oban.Testing, unquote(opts)
      import AshOban.Test
    end
  end

  @doc """
  Asserts that an Oban job has been enqueued for the given record and trigger.

  Returns the list of matching `Oban.Job` structs so you can make further
  assertions on job properties if needed.

  Requires `all_enqueued/1` to be in scope — use `use AshOban.Test` or
  `use Oban.Testing` to set this up.

  ## Options

  Additional options are merged with the trigger-derived options (`:worker`,
  `:args`) and forwarded to `all_enqueued/1`. Use these to narrow the
  assertion:

  * `:queue` - assert the job is in a specific queue
  * `:state` - assert the job is in a specific state
  * `:priority` - assert the job has a specific priority

  ## Examples

      {:ok, appointment} = Appointment.update(appointment, params)
      assert_triggered(appointment, :create_zoom_meeting)

      # Narrow to a specific queue
      assert_triggered(appointment, :create_zoom_meeting, queue: :zoom_api)

      # Further assert on the returned jobs
      [job] = assert_triggered(appointment, :create_zoom_meeting)
      assert job.priority == 2
  """
  defmacro assert_triggered(record, trigger_name, opts \\ []) do
    quote do
      record_val = unquote(record)
      resource = record_val.__struct__
      trigger_name_val = unquote(trigger_name)

      trigger = AshOban.Test.__fetch_trigger__!(resource, trigger_name_val)

      primary_key = Ash.Resource.Info.primary_key(resource)
      pk_map = Map.new(primary_key, fn key -> {key, Map.get(record_val, key)} end)

      enqueued_opts =
        Keyword.merge(
          [worker: trigger.worker, args: %{primary_key: pk_map}],
          unquote(opts)
        )

      matching = all_enqueued(enqueued_opts)

      ExUnit.Assertions.assert(
        matching != [],
        "Expected an Oban job to be enqueued for trigger #{inspect(trigger_name_val)} on " <>
          "#{inspect(resource)} with primary key #{inspect(pk_map)}, but none was found"
      )

      matching
    end
  end

  @doc """
  Refutes that an Oban job has been enqueued for the given record and trigger.

  Requires `all_enqueued/1` to be in scope — use `use AshOban.Test` or
  `use Oban.Testing` to set this up.

  ## Options

  Additional options are merged with the trigger-derived options (`:worker`,
  `:args`) and forwarded to `all_enqueued/1`. Use these to narrow the
  assertion:

  * `:queue` - refute that the job is in a specific queue
  * `:state` - refute that the job is in a specific state
  * `:priority` - refute that the job has a specific priority

  ## Examples

      refute_triggered(appointment, :create_zoom_meeting)

      # Narrow to a specific queue
      refute_triggered(appointment, :create_zoom_meeting, queue: :zoom_api)
  """
  defmacro refute_triggered(record, trigger_name, opts \\ []) do
    quote do
      record_val = unquote(record)
      resource = record_val.__struct__
      trigger_name_val = unquote(trigger_name)

      trigger = AshOban.Test.__fetch_trigger__!(resource, trigger_name_val)

      primary_key = Ash.Resource.Info.primary_key(resource)
      pk_map = Map.new(primary_key, fn key -> {key, Map.get(record_val, key)} end)

      enqueued_opts =
        Keyword.merge(
          [worker: trigger.worker, args: %{primary_key: pk_map}],
          unquote(opts)
        )

      matching = all_enqueued(enqueued_opts)

      ExUnit.Assertions.assert(
        matching == [],
        "Expected no Oban jobs to be enqueued for trigger #{inspect(trigger_name_val)} on " <>
          "#{inspect(resource)} with primary key #{inspect(pk_map)}, " <>
          "but #{length(matching)} job(s) were found"
      )
    end
  end

  @doc false
  def __fetch_trigger__!(resource, trigger_name) do
    case AshOban.Info.oban_trigger(resource, trigger_name) do
      nil ->
        raise ArgumentError,
              "No trigger named #{inspect(trigger_name)} found for resource #{inspect(resource)}"

      trigger ->
        trigger
    end
  end

  @doc """
  Schedules and runs triggers, draining queues by default.

  This is a wrapper around `AshOban.schedule_and_run_triggers/2` with
  `drain_queues?: true` set by default, making it suitable for use in tests
  where you want jobs to execute synchronously.

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

  @doc """
  Asserts that the given record currently matches a trigger's `where` filter,
  meaning the scheduler would enqueue a job for it if it ran now.

  This does **not** check whether a job has already been enqueued — use
  `assert_triggered/3` for that. Instead, it checks the record's current
  state in the database against the trigger's filter expression.

  Returns the matched record.

  ## Options

  * `:actor` - The actor to use when reading the record. Defaults to `nil`.
  * `:tenant` - The tenant to use when reading the record. Defaults to `nil`.
  * `:domain` - The domain to use when reading. Defaults to the resource's
    configured Oban domain.

  ## Examples

      # After creating a record, assert it is eligible for scheduling
      record = MyApp.create_record!()
      assert_would_schedule(record, :process)

      # After processing, assert it is no longer eligible
      processed = MyApp.process!(record)
      refute_would_schedule(processed, :process)
  """
  def assert_would_schedule(%resource{} = record, trigger_name, opts \\ []) do
    trigger = __fetch_trigger__!(resource, trigger_name)

    primary_key = Ash.Resource.Info.primary_key(resource)
    pk_filter = Map.take(record, primary_key)

    result = query_for_scheduling(resource, trigger, pk_filter, opts)

    ExUnit.Assertions.assert(
      result != nil,
      "Expected #{inspect(resource)} record with primary key #{inspect(pk_filter)} " <>
        "to match the where filter for trigger #{inspect(trigger_name)}, but it does not"
    )

    result
  end

  @doc """
  Refutes that the given record currently matches a trigger's `where` filter.

  This is the inverse of `assert_would_schedule/3`. It asserts that the
  scheduler would **not** enqueue a job for the record if it ran now.

  ## Options

  * `:actor` - The actor to use when reading the record. Defaults to `nil`.
  * `:tenant` - The tenant to use when reading the record. Defaults to `nil`.
  * `:domain` - The domain to use when reading. Defaults to the resource's
    configured Oban domain.

  ## Examples

      processed = MyApp.process!(record)
      refute_would_schedule(processed, :process)
  """
  def refute_would_schedule(%resource{} = record, trigger_name, opts \\ []) do
    trigger = __fetch_trigger__!(resource, trigger_name)

    primary_key = Ash.Resource.Info.primary_key(resource)
    pk_filter = Map.take(record, primary_key)

    result = query_for_scheduling(resource, trigger, pk_filter, opts)

    ExUnit.Assertions.assert(
      result == nil,
      "Expected #{inspect(resource)} record with primary key #{inspect(pk_filter)} " <>
        "to NOT match the where filter for trigger #{inspect(trigger_name)}, but it does"
    )
  end

  defp query_for_scheduling(resource, trigger, pk_filter, opts) do
    domain = opts[:domain] || AshOban.Info.oban_domain!(resource)
    read_action = trigger.read_action || Ash.Resource.Info.primary_action!(resource, :read).name

    resource
    |> Ash.Query.do_filter(pk_filter)
    |> then(fn query ->
      if trigger.where do
        Ash.Query.do_filter(query, trigger.where)
      else
        query
      end
    end)
    |> Ash.Query.for_read(read_action, %{},
      authorize?: false,
      actor: opts[:actor],
      domain: domain
    )
    |> Ash.Query.set_tenant(opts[:tenant])
    |> Ash.read_one!()
  end
end
