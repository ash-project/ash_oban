# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Oban.Pro.Workers.Chunk) do
  defmodule AshOban.ChunksTest do
    @moduledoc false
    use ExUnit.Case, async: false
    @moduletag :oban_pro

    alias AshOban.Test.TriggeredChunks

    setup_all do
      AshOban.Test.Repo.start_link()

      Oban.start_link(
        AshOban.config(
          [AshOban.Test.DomainChunks],
          Application.get_env(:ash_oban, :oban_pro)
        )
      )

      :ok
    end

    setup do
      Oban.delete_all_jobs(Oban.Job)
      :ok
    end

    test "chunk worker processes all records in a batch via bulk update" do
      {:ok, agent} = Agent.start_link(fn -> [] end)
      Process.put(:batch_tracker_agent, agent)

      records =
        for _ <- 1..5 do
          TriggeredChunks
          |> Ash.Changeset.for_create(:create, %{})
          |> Ash.create!()
        end

      AshOban.Test.schedule_and_run_triggers({TriggeredChunks, :process})

      for record <- records do
        updated = Ash.get!(TriggeredChunks, record.id)
        assert updated.processed == true
      end

      # All 5 records passed through the batch change in one batch_change/3 call
      processed_ids = Agent.get(agent, & &1)
      assert length(processed_ids) == 5
      assert MapSet.new(processed_ids) == MapSet.new(Enum.map(records, & &1.id))

      Agent.stop(agent)
    end

    test "records that no longer match the where clause are discarded" do
      already_processed =
        TriggeredChunks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      to_process =
        TriggeredChunks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      # Mark one as already processed so it won't be scheduled
      Ash.update!(already_processed, action: :process)

      result = AshOban.Test.schedule_and_run_triggers({TriggeredChunks, :process})

      assert result.success >= 1

      updated = Ash.get!(TriggeredChunks, to_process.id)
      assert updated.processed == true
    end

    test "on_error is called for final-attempt failures" do
      record =
        TriggeredChunks
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.Test.schedule_and_run_triggers({TriggeredChunks, :process_with_on_error})

      updated = Ash.get!(TriggeredChunks, record.id)
      assert updated.errored == true
      assert updated.processed == false
    end

    test "chunk trigger metadata is correct" do
      trigger = AshOban.Info.oban_trigger(TriggeredChunks, :process)
      assert trigger.chunks != nil
      assert trigger.chunks.size == 10
      assert trigger.chunks.timeout == 100
      assert function_exported?(trigger.worker, :process, 1)
    end
  end
end
