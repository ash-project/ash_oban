# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.TriggeredPro do
  @moduledoc """
  A resource to test oban triggers with pro features.
  """
  use Ash.Resource,
    domain: AshOban.Test.DomainPro,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    global? true
  end

  oban do
    triggers do
      trigger :process_with_state do
        state :paused
        trigger_once? true
        action :process_with_state
        where expr(processed != true)
        sort inserted_at: :asc
        max_attempts 2

        extra_args(fn _record ->
          %{extra_arg: 1}
        end)

        worker_read_action :read
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.ProcessWithState
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.ProcessWithState
      end
    end
  end

  policies do
    policy action(:process) do
      authorize_if actor_present()
    end

    policy always() do
      authorize_if always()
    end
  end

  actions do
    defaults create: [:tenant_id]

    read :read do
      primary? true
      pagination keyset?: true
    end

    update :process_with_state do
      require_atomic? false
      change set_attribute(:processed, true)
      argument :special_arg, :string

      change fn changeset, context ->
        if changeset.arguments[:special_arg] do
          send(self(), {:special_arg, changeset.arguments[:special_arg]})
        end

        send(self(), {:actor, context.actor})
        changeset
      end
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :processed, :boolean, default: false, allow_nil?: false
    attribute :number, :integer, public?: true
    attribute :tenant_id, :integer, allow_nil?: false, default: 1
    timestamps()
  end

  defimpl Ash.ToTenant do
    def to_tenant(%{tenant_id: id}, _resource), do: id
  end
end
