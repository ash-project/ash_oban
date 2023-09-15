defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  @mix_app Mix.Project.config()[:app]

  def schedule_and_run_triggers() do
    @mix_app
    |> IO.inspect()
    |> Application.get_env(:ash_apis, [])
    |> IO.inspect()
    |> List.wrap()
    |> Enum.reduce(%{}, fn api, acc ->
      api
      |> schedule_and_run_triggers()
      |> Map.merge(acc, fn _key, left, right ->
        left + right
      end)
    end)
  end

  def schedule_and_run_triggers(resource_or_api) do
    if Spark.Dsl.is?(resource_or_api, Ash.Api) do
      resource_or_api
      |> Ash.Api.Info.resources()
      |> Enum.reduce(%{}, fn resource, acc ->
        resource
        |> schedule_and_run_triggers()
        |> Map.merge(acc, fn _key, left, right ->
          left + right
        end)
      end)
    else
      triggers =
        AshOban.Info.oban_triggers(resource_or_api)

      Enum.each(triggers, fn trigger ->
        AshOban.schedule(resource_or_api, trigger)
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
    end
  end
end
