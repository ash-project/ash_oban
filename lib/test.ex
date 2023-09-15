defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  def schedule_and_run_triggers(resource_or_api_or_otp_app) do
    cond do
      Spark.Dsl.is?(resource_or_api_or_otp_app, Ash.Api) ->
        resource_or_api_or_otp_app
        |> Ash.Api.Info.resources()
        |> Enum.reduce(%{}, fn resource, acc ->
          resource
          |> IO.inspect()
          |> schedule_and_run_triggers()
          |> Map.merge(acc, fn _key, left, right ->
            left + right
          end)
        end)

      Spark.Dsl.is?(resource_or_api_or_otp_app, Ash.Resource) ->
        triggers =
          resource_or_api_or_otp_app
          |> AshOban.Info.oban_triggers()
          |> Enum.filter(fn trigger ->
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
          IO.inspect(api)

          api
          |> schedule_and_run_triggers()
          |> Map.merge(acc, fn _key, left, right ->
            left + right
          end)
        end)
    end
  end
end
