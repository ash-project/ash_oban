defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  def schedule_and_run_triggers(resource) do
    triggers =
      AshOban.Info.oban_triggers(resource)

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
      |> Oban.drain_queue()
      |> Map.merge(acc, fn _key, left, right ->
        left + right
      end)
    end)
  end
end
