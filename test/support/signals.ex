# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Signals do
  @moduledoc false
  use Ash.Signals

  defmodule RenameUpgrader do
    @moduledoc false
    use AshOban.Signals.Upgrader

    @impl true
    def upgrade(%{"old_order_id" => order_id} = signal, _opts) do
      {:ok, signal |> Map.delete("old_order_id") |> Map.put("order_id", order_id)}
    end

    def upgrade(signal, _opts), do: {:ok, signal}
  end

  signals do
    signal :order_placed do
      argument :order_id, :uuid, allow_nil?: false
      argument :note, :string
    end

    signal :orders_batched do
      argument :order_id, :uuid, allow_nil?: false
    end

    signal :order_unique do
      argument :order_id, :uuid, allow_nil?: false
    end

    signal :order_renamed do
      argument :order_id, :uuid, allow_nil?: false
    end

    signal :orders_chunked do
      argument :order_id, :uuid, allow_nil?: false
    end

    signal :order_routed do
      argument :order_id, :uuid, allow_nil?: false
    end

    # Only listened to by resources compiled in verification tests.
    signal :verified do
      argument :order_id, :uuid, allow_nil?: false
    end
  end
end

defmodule AshOban.Test.Order do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :note, :string, public?: true
  end

  actions do
    defaults [:read]

    create :place do
      accept [:note]

      emit AshOban.Test.Signals, :order_placed, fields: [order_id: :id]
    end

    create :place_again do
      accept [:note]
      argument :signal_id, :uuid_v7, allow_nil?: false
      emit AshOban.Test.Signals, :order_placed, dynamic?: true

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn changeset, order ->
          with :ok <-
                 Ash.Signals.emit(changeset, AshOban.Test.Signals, :order_placed, %{
                   signal_id: Ash.Changeset.get_argument(changeset, :signal_id),
                   order_id: order.id
                 }) do
            {:ok, order}
          end
        end)
      end
    end

    create :place_batched do
      emit AshOban.Test.Signals, :orders_batched, fields: [order_id: :id]
    end

    create :place_unique do
      argument :order_id, :uuid, allow_nil?: false

      emit AshOban.Test.Signals, :order_unique, values: [order_id: arg(:order_id)]
    end

    create :place_chunked do
      emit AshOban.Test.Signals, :orders_chunked, fields: [order_id: :id]
    end

    create :place_routed do
      emit AshOban.Test.Signals, :order_routed, fields: [order_id: :id]
    end
  end
end

defmodule AshOban.Test.SignalReceipt do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  signals_in do
    from AshOban.Test.Signals do
      on :order_placed, :record, delivery: {AshOban.Signals, queue: :signals}
      on :order_placed, :notify, delivery: {AshOban.Signals, queue: :signals}
      on :order_placed, :notify_inline

      on :orders_batched, :notify_all,
        batch?: true,
        delivery: {AshOban.Signals, queue: :signals}

      on :order_unique, :record_unique,
        action: :record,
        delivery: {AshOban.Signals, queue: :signals, unique: [keys: [:order_id]]}

      on :order_renamed, :record_renamed,
        action: :record,
        delivery:
          {AshOban.Signals, queue: :signals, upgrader: AshOban.Test.Signals.RenameUpgrader}

      on :order_routed, :notify_routed,
        delivery: {AshOban.Signals, queue: :signals, oban: AshOban.Test.OtherOban}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :order_id, :uuid, public?: true
    attribute :note, :string, public?: true
    attribute :actor_id, :string, public?: true
  end

  actions do
    defaults [:read]

    create :record do
      accept [:order_id, :note]
      change set_attribute(:actor_id, actor(:id))
    end

    action :notify do
      argument :signal, AshOban.Test.Signals.OrderPlaced, allow_nil?: false

      run fn input, context ->
        send(self(), {:notified, input.arguments.signal, context.actor, context.tenant})
        send(self(), {:notified_signal_path, input.context[:signal_path]})
        :ok
      end
    end

    action :notify_inline do
      argument :signal, AshOban.Test.Signals.OrderPlaced, allow_nil?: false

      run fn input, _context ->
        send(self(), {:notified_inline, input.arguments.signal})
        :ok
      end
    end

    action :notify_all do
      argument :signals, {:array, AshOban.Test.Signals.OrdersBatched}, allow_nil?: false

      run fn input, _context ->
        send(self(), {:notified_all, input.arguments.signals})
        :ok
      end
    end

    action :notify_routed do
      argument :signal, AshOban.Test.Signals.OrderRouted, allow_nil?: false

      run fn input, _context ->
        send(self(), {:notified_routed, input.arguments.signal})
        :ok
      end
    end
  end
end

# Listens to a signal that is never emitted, so that `AshOban.config/3` can be tested against
# a domain with a signal listener.
defmodule AshOban.Test.QueuedSignalListener do
  @moduledoc false
  use Ash.Resource, domain: AshOban.Test.SignalsDomain

  signals_in do
    from AshOban.Test.Signals do
      on :verified, :notify, delivery: {AshOban.Signals, queue: :signals}

      # Uses another instance, so `AshOban.config/3` for `Oban` doesn't require its queue.
      on :verified, :notify_elsewhere,
        action: :notify,
        delivery: {AshOban.Signals, queue: :elsewhere, oban: AshOban.Test.OtherOban}
    end
  end

  actions do
    action :notify do
      argument :signal, AshOban.Test.Signals.Verified, allow_nil?: false
      run fn _input, _context -> :ok end
    end
  end
end

defmodule AshOban.Test.SignalsDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshOban.Test.QueuedSignalListener
  end
end

if AshOban.Info.pro?() and Code.ensure_loaded?(Oban.Pro.Workers.Chunk) do
  defmodule AshOban.Test.ChunkedSignalReceipt.ReportBatch do
    @moduledoc false
    use Ash.Resource.Change

    @impl true
    def batch_change(changesets, _opts, _context) do
      send(self(), {:recorded_batch, length(changesets)})
      changesets
    end
  end

  defmodule AshOban.Test.ChunkedSignalReceipt do
    @moduledoc false
    use Ash.Resource,
      domain: AshOban.Test.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    ets do
      private? true
    end

    signals_in do
      from AshOban.Test.Signals do
        on :orders_chunked, :notify_chunk,
          batch?: true,
          delivery: {AshOban.Signals, queue: :signal_chunks, chunks: [size: 10, timeout: 100]}

        on :orders_chunked, :record_chunk,
          action: :record,
          delivery: {AshOban.Signals, queue: :signal_chunks, chunks: [size: 10, timeout: 100]}
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :order_id, :uuid, public?: true
    end

    actions do
      defaults [:read]

      create :record do
        accept [:order_id]
        change AshOban.Test.ChunkedSignalReceipt.ReportBatch
      end

      action :notify_chunk do
        argument :signals, {:array, AshOban.Test.Signals.OrdersChunked}, allow_nil?: false

        run fn input, _context ->
          send(self(), {:notified_chunk, input.arguments.signals})
          :ok
        end
      end
    end
  end
end
