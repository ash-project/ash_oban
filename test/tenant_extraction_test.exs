# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.TenantExtractionTest.TestResource do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.TenantExtractionTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshOban]

  multitenancy do
    strategy :attribute
    attribute :tenant_id
  end

  oban do
    triggers do
      trigger :process_with_tenant do
        action :process
        where expr(processed != true)
        read_action :read_global
        worker_read_action :read_with_tenant
        queue :default
        use_tenant_from_record? true

        worker_module_name __MODULE__.AshOban.Worker.ProcessWithTenant

        scheduler_module_name __MODULE__.AshOban.Scheduler.ProcessWithTenant
      end
    end
  end

  actions do
    default_accept []
    defaults [:read, :destroy]

    create :create do
      accept [:tenant_id]
    end

    read :read_global do
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :read_with_tenant do
      pagination keyset?: true
    end

    update :process do
      require_atomic? false
      accept []
      change set_attribute(:processed, true)
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :processed, :boolean, default: false, allow_nil?: false
    attribute :tenant_id, :integer, allow_nil?: false, default: 1
    timestamps()
  end
end

defmodule AshOban.TenantExtractionTest.TestResourceWithCustomTenantFunctions do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.TenantExtractionTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshOban]

  multitenancy do
    strategy :attribute
    attribute :tenant_id
    parse_attribute({__MODULE__, :parse_tenant, []})
    tenant_from_attribute({__MODULE__, :format_tenant, []})
  end

  oban do
    triggers do
      trigger :process_with_custom_tenant do
        action :process
        where expr(processed != true)
        read_action :read_global
        worker_read_action :read_with_tenant
        queue :custom
        use_tenant_from_record? true

        worker_module_name __MODULE__.AshOban.Worker.ProcessWithCustomTenant

        scheduler_module_name __MODULE__.AshOban.Scheduler.ProcessWithCustomTenant
      end
    end
  end

  actions do
    default_accept []
    defaults [:read, :destroy]

    create :create do
      accept [:tenant_id]
    end

    read :read_global do
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :read_with_tenant do
      pagination keyset?: true
    end

    update :process do
      require_atomic? false
      accept []
      change set_attribute(:processed, true)
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :processed, :boolean, default: false, allow_nil?: false
    attribute :tenant_id, :integer, allow_nil?: false, default: 1
    timestamps()
  end

  def parse_tenant("org_" <> id_string), do: String.to_integer(id_string)
  def parse_tenant(value) when is_integer(value), do: value

  def format_tenant(id) when is_integer(id), do: "org_#{id}"
  def format_tenant("org_" <> _ = value), do: value
end

defmodule AshOban.TenantExtractionTest.TestDomain do
  @moduledoc false
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshOban.TenantExtractionTest.TestResource
    resource AshOban.TenantExtractionTest.TestResourceWithCustomTenantFunctions
  end
end

defmodule AshOban.TenantExtractionTest do
  use ExUnit.Case, async: false

  use Oban.Testing, repo: AshOban.Test.Repo, prefix: "private"

  require Ash.Query

  alias AshOban.TenantExtractionTest.TestDomain
  alias AshOban.TenantExtractionTest.TestResource

  setup_all do
    AshOban.Test.Repo.start_link()

    oban_config =
      Application.get_env(:ash_oban, :oban)
      |> Keyword.update(:queues, [default: 10, custom: 10], fn queues ->
        Keyword.put(queues, :custom, 10)
      end)

    Oban.start_link(AshOban.config([TestDomain], oban_config))
    :ok
  end

  setup do
    on_exit(fn ->
      AshOban.Test.Repo.delete_all(Oban.Job, prefix: "private")
    end)
  end

  describe "tenant extraction from records" do
    test "scheduler reads globally, worker uses extracted tenant from each record" do
      record1 =
        TestResource
        |> Ash.Changeset.for_create(:create, %{}, tenant: 1)
        |> Ash.create!()

      record2 =
        TestResource
        |> Ash.Changeset.for_create(:create, %{}, tenant: 2)
        |> Ash.create!()

      record3 =
        TestResource
        |> Ash.Changeset.for_create(:create, %{}, tenant: 3)
        |> Ash.create!()

      assert %{success: 4} =
               AshOban.Test.schedule_and_run_triggers({TestResource, :process_with_tenant})

      assert Ash.reload!(record1).processed
      assert Ash.reload!(record2).processed
      assert Ash.reload!(record3).processed
    end

    test "tenant extraction works with custom parse_attribute and tenant_from_attribute functions" do
      alias AshOban.TenantExtractionTest.TestResourceWithCustomTenantFunctions

      record1 =
        TestResourceWithCustomTenantFunctions
        |> Ash.Changeset.for_create(:create, %{}, tenant: "org_100")
        |> Ash.create!()

      record2 =
        TestResourceWithCustomTenantFunctions
        |> Ash.Changeset.for_create(:create, %{}, tenant: "org_200")
        |> Ash.create!()

      record3 =
        TestResourceWithCustomTenantFunctions
        |> Ash.Changeset.for_create(:create, %{}, tenant: "org_300")
        |> Ash.create!()

      assert record1.tenant_id == 100
      assert record2.tenant_id == 200
      assert record3.tenant_id == 300

      assert %{success: 4} =
               AshOban.Test.schedule_and_run_triggers(
                 {TestResourceWithCustomTenantFunctions, :process_with_custom_tenant}
               )

      assert Ash.reload!(record1, tenant: "org_100").processed
      assert Ash.reload!(record2, tenant: "org_200").processed
      assert Ash.reload!(record3, tenant: "org_300").processed
    end
  end
end
