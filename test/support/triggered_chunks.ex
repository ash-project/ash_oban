# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Oban.Pro.Workers.Chunk) do
  defmodule AshOban.Test.DomainChunks do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.Test.TriggeredChunks
    end
  end

  # A custom change that demonstrates batch-aware processing:
  # on atomic/bulk paths it inserts all IDs at once rather than one at a time.
  defmodule AshOban.Test.BatchTracker do
    @moduledoc false
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        record = changeset.data
        agent = Process.get(:batch_tracker_agent)
        if agent, do: Agent.update(agent, &[record.id | &1])
        changeset
      end)
    end

    def atomic(_changeset, _opts, _context), do: {:not_atomic, "tracking in test"}

    def batch_change(changesets, _opts, _context) do
      agent = Process.get(:batch_tracker_agent)

      if agent do
        ids = Enum.map(changesets, fn cs -> cs.data.id end)
        Agent.update(agent, &(ids ++ &1))
      end

      changesets
    end
  end

  defmodule AshOban.Test.TriggeredChunks do
    @moduledoc """
    A resource for testing chunk-based trigger processing with Oban Pro.
    """
    use Ash.Resource,
      domain: AshOban.Test.DomainChunks,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        trigger :process do
          action :process
          where expr(processed != true)
          max_attempts 2
          worker_read_action :read
          worker_module_name AshOban.Test.TriggeredChunks.AshOban.Worker.Process
          scheduler_module_name AshOban.Test.TriggeredChunks.AshOban.Scheduler.Process

          chunks do
            size(10)
            timeout 100
          end
        end

        trigger :process_with_on_error do
          action :process_failure
          on_error :mark_errored
          where expr(processed != true and errored != true)
          max_attempts 1
          worker_read_action :read
          worker_module_name AshOban.Test.TriggeredChunks.AshOban.Worker.ProcessWithOnError
          scheduler_module_name AshOban.Test.TriggeredChunks.AshOban.Scheduler.ProcessWithOnError

          chunks do
            size(10)
            timeout 100
          end
        end
      end
    end

    actions do
      defaults create: []

      read :read do
        primary? true
        pagination keyset?: true
      end

      update :process do
        require_atomic? false
        change set_attribute(:processed, true)
        change AshOban.Test.BatchTracker
      end

      update :process_failure do
        require_atomic? false

        change after_action(fn _changeset, _record, _context ->
                 {:error, "intentional failure for testing"}
               end)
      end

      update :mark_errored do
        require_atomic? false
        change set_attribute(:errored, true)
      end
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :processed, :boolean, default: false, allow_nil?: false, public?: true
      attribute :errored, :boolean, default: false, allow_nil?: false, public?: true
      timestamps()
    end
  end
end
