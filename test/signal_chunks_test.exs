# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if AshOban.Info.pro?() and Code.ensure_loaded?(Oban.Pro.Workers.Chunk) do
  defmodule AshOban.SignalChunksTest do
    use ExUnit.Case, async: false
    use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"
    @moduletag :oban_pro

    alias AshOban.Test.{ChunkedSignalReceipt, Order, Signals}

    setup_all do
      Oban.start_link(AshOban.config([], Application.get_env(:ash_oban, :oban_pro)))

      :ok
    end

    setup do
      Oban.delete_all_jobs(Oban.Job)
      :ok
    end

    test "each signal gets its own job, and a chunk runs the listener with all of them" do
      Ash.bulk_create!([%{}, %{}, %{}], Order, :place_chunked)

      worker = AshOban.Signals.chunk_worker(ChunkedSignalReceipt, :notify_chunk)
      assert [_, _, _] = all_enqueued(worker: worker, queue: :signal_chunks)

      # Draining one job at a time leaves the rest available for each chunk to gather.
      assert %{failure: 0, discard: 0} =
               Oban.drain_queue(queue: :signal_chunks, with_limit: 1, with_recursion: true)

      assert_received {:notified_chunk, [%Signals.OrdersChunked{} | _] = signals}
      assert length(signals) == 3
      refute_received {:notified_chunk, _}
    end

    test "a chunked create listener creates the records of a chunk with one bulk create" do
      orders = Ash.bulk_create!([%{}, %{}, %{}], Order, :place_chunked, return_records?: true)

      worker = AshOban.Signals.chunk_worker(ChunkedSignalReceipt, :record_chunk)
      assert [_, _, _] = all_enqueued(worker: worker, queue: :signal_chunks)

      assert %{failure: 0, discard: 0} =
               Oban.drain_queue(queue: :signal_chunks, with_limit: 1, with_recursion: true)

      assert_received {:recorded_batch, 3}
      refute_received {:recorded_batch, _}

      assert ChunkedSignalReceipt |> Ash.read!() |> Enum.map(& &1.order_id) |> Enum.sort() ==
               orders.records |> Enum.map(& &1.id) |> Enum.sort()
    end
  end
end
