# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
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

        worker_module_name AshOban.TenantExtractionTest.TestResource.AshOban.Worker.ProcessWithTenant

        scheduler_module_name AshOban.TenantExtractionTest.TestResource.AshOban.Scheduler.ProcessWithTenant
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
      # Standard read that requires tenant
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

defmodule AshOban.TenantExtractionTest.TestDomain do
  @moduledoc false
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshOban.TenantExtractionTest.TestResource
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
    Oban.start_link(AshOban.config([TestDomain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    Oban.drain_queue(queue: :default)
    :ok
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
  end
end
