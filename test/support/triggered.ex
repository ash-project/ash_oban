defmodule AshOban.Test.Triggered do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  oban do
    triggers do
      trigger :process do
        action :process
        where expr(processed != true)
        max_attempts 2
        worker_read_action(:read)
      end

      trigger :process_2 do
        action :process
        where expr(processed != true)
        max_attempts 2
        worker_read_action(:read)
        scheduler_cron false
      end
    end

    scheduled_actions do
      schedule :say_hello, "0 0 1 1 *"
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
    defaults [:create]

    read :read do
      primary? true
      pagination keyset?: true
    end

    update :process do
      change set_attribute(:processed, true)

      change fn changeset, context ->
        send(self(), {:actor, context.actor})
        changeset
      end
    end

    action :say_hello, :string do
      run fn input, _ ->
        {:ok, "Hello"}
      end
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :processed, :boolean, default: false, allow_nil?: false
  end
end
