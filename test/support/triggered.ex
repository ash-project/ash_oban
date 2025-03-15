defmodule AshOban.Test.Triggered do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.Test.Domain,
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
      trigger :process do
        trigger_once? true
        action :process
        where expr(processed != true)
        sort inserted_at: :asc
        max_attempts 2

        extra_args(fn _record ->
          %{extra_arg: 1}
        end)

        worker_read_action :read
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.Process
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.Process
      end

      trigger :process_atomically do
        extra_args fn
          %{number: number} when is_number(number) ->
            %{number: number}

          _ ->
            %{}
        end

        action :process_atomically
        queue :triggered_process
        where expr(processed != true)
        max_attempts 2
        worker_read_action(:read)
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.ProcessAtomically
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.ProcessAtomically
      end

      trigger :process_2 do
        action :process
        where expr(processed != true)
        max_attempts 2
        worker_read_action(:read)
        scheduler_cron false
        worker_opts tags: ["tag1", "tag2"]
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.Process2
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.Process2
      end

      trigger :process_generic do
        action :say_hello
        max_attempts 2
        scheduler_cron "* * * * *"
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.ProcessGeneric
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.ProcessGeneric
      end

      trigger :tenant_aware do
        list_tenants fn ->
          [2]
        end

        action :process_atomically
        worker_module_name AshOban.Test.Triggered.AshOban.Worker.TenantAware
        scheduler_module_name AshOban.Test.Triggered.AshOban.Scheduler.TenantAware
      end
    end

    scheduled_actions do
      schedule :say_hello, "0 0 1 1 *" do
        worker_module_name AshOban.Test.Triggered.AshOban.ActionWorker.SayHello
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

    create :bulk_create do
      accept [:number]
      change run_oban_trigger(:process_atomically)
    end

    update :update_triggered do
      change set_attribute(:processed, true)
      change run_oban_trigger(:process_atomically)
    end

    update :process_atomically do
      change set_attribute(:processed, true)
    end

    update :process do
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
    attribute :number, :integer, public?: true
    attribute :tenant_id, :integer, allow_nil?: false, default: 1
    timestamps()
  end

  defimpl Ash.ToTenant do
    def to_tenant(%{tenant_id: id}, _resource), do: id
  end
end
