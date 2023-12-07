defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  @type triggerable :: Ash.Resource.t() | {Ash.Resource.t(), atom()} | Ash.Api.t() | atom()
  @type result :: %{
          discard: non_neg_integer(),
          cancelled: non_neg_integer(),
          success: non_neg_integer(),
          failure: non_neg_integer(),
          snoozed: non_neg_integer()
        }

  @doc """
  Runs the schedulers for the given resource, api, or otp_app, or list of resources, apis, or otp_apps.

  Options:

  - `queue`, `with_limit`, `with_recursion`, `with_safety`, `with_scheduled` - passed through to `Oban.drain_queue/2`
  - `scheduled_actions?` - Defaults to false, unless a scheduled action name was explicitly provided. Schedules all applicable scheduled actions.
  - `triggers?` - Defaults to true, schedules all applicable scheduled actions.

  If the input is:
  * a list - each item is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * an otp_app - each api configured in the `ash_apis` of that otp_app is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * an api - each reosurce configured in that api is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * a tuple of {resource, :trigger_name} - that trigger is scheduled, and the results are merged together.
  * a resource - each trigger configured in that resource is scheduled, and the results are merged together.
  """
  @spec schedule_and_run_triggers(triggerable | list(triggerable), keyword()) :: result
  def schedule_and_run_triggers(resources_or_apis_or_otp_apps, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:scheduled_actions?, false)
      |> Keyword.put_new(:triggers?, true)

    do_schedule_and_run_triggers(resources_or_apis_or_otp_apps, opts)
  end

  def do_schedule_and_run_triggers(resources_or_apis_or_otp_apps, opts)
      when is_list(resources_or_apis_or_otp_apps) do
    Enum.reduce(resources_or_apis_or_otp_apps, %{}, fn item, acc ->
      item
      |> do_schedule_and_run_triggers(opts)
      |> Map.merge(acc, fn _key, left, right ->
        left + right
      end)
    end)
  end

  def do_schedule_and_run_triggers({resource, trigger_name}, opts) do
    triggers =
      resource
      |> AshOban.Info.oban_triggers_and_scheduled_actions()
      |> Enum.filter(fn
        %AshOban.Schedule{name: name} ->
          name == trigger_name

        trigger ->
          trigger.scheduler && trigger.name == trigger_name
      end)

    Enum.each(triggers, fn trigger ->
      AshOban.schedule(resource, trigger)
    end)

    queues =
      triggers
      |> Enum.map(& &1.queue)
      |> Enum.uniq()

    # we drain each queue twice to do schedulers and then workers
    Enum.reduce(queues ++ queues, %{}, fn queue, acc ->
      [queue: queue]
      |> Keyword.merge(
        Keyword.take(opts, [:queue, :with_limit, :with_recursion, :with_safety, :with_scheduled])
      )
      |> Oban.drain_queue()
      |> Map.merge(acc, fn _key, left, right ->
        left + right
      end)
    end)
  end

  def do_schedule_and_run_triggers(resource_or_api_or_otp_app, opts) do
    cond do
      Spark.Dsl.is?(resource_or_api_or_otp_app, Ash.Api) ->
        resource_or_api_or_otp_app
        |> Ash.Api.Info.resources()
        |> Enum.reduce(%{}, fn resource, acc ->
          resource
          |> do_schedule_and_run_triggers(opts)
          |> Map.merge(acc, fn _key, left, right ->
            left + right
          end)
        end)

      Spark.Dsl.is?(resource_or_api_or_otp_app, Ash.Resource) ->
        triggers =
          resource_or_api_or_otp_app
          |> AshOban.Info.oban_triggers_and_scheduled_actions()
          |> Enum.filter(fn
            %AshOban.Schedule{} ->
              opts[:scheduled_actions?] && true

            trigger ->
              trigger.scheduler
          end)

        Enum.each(triggers, fn trigger ->
          AshOban.schedule(resource_or_api_or_otp_app, trigger)
        end)

        queues =
          triggers
          |> Enum.map(& &1.queue)
          |> Enum.uniq()

        # we drain each queue twice to do schedulers and then workers
        Enum.reduce(queues ++ queues, %{}, fn queue, acc ->
          [queue: queue]
          |> Keyword.merge(opts)
          |> Oban.drain_queue()
          |> Map.merge(acc, fn _key, left, right ->
            left + right
          end)
        end)

      true ->
        resource_or_api_or_otp_app
        |> Application.get_env(:ash_apis, [])
        |> List.wrap()
        |> Enum.reduce(%{}, fn api, acc ->
          api
          |> do_schedule_and_run_triggers(opts)
          |> Map.merge(acc, fn _key, left, right ->
            left + right
          end)
        end)
    end
  end
end
