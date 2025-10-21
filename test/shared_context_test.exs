# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.SharedContextTest do
  use ExUnit.Case, async: false

  use Oban.Testing, repo: AshOban.Test.Repo, prefix: "private"

  require Ash.Query

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.SharedContextTest.RelationshipTarget
      resource AshOban.SharedContextTest.TriggeredWithRelationship
    end
  end

  defmodule RelationshipTarget do
    use Ash.Resource,
      domain: AshOban.SharedContextTest.TestDomain,
      data_layer: Ash.DataLayer.Mnesia,
      authorizers: [Ash.Policy.Authorizer]

    policies do
      bypass AshOban.Checks.AshObanInteraction do
        authorize_if always()
      end

      policy always() do
        forbid_if always()
      end
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:name, :triggered_with_relationship_id]
      end

      update :update do
        primary? true
        accept [:name]
      end
    end

    mnesia do
      table :triggered
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      timestamps()
    end

    relationships do
      belongs_to :triggered_with_relationship,
                 AshOban.SharedContextTest.TriggeredWithRelationship do
        writable? true
        public? true
      end
    end
  end

  defmodule TriggeredWithRelationship do
    @moduledoc false
    use Ash.Resource,
      domain: AshOban.SharedContextTest.TestDomain,
      data_layer: Ash.DataLayer.Mnesia,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshOban]

    oban do
      triggers do
        trigger :process_with_shared_context do
          shared_context? true
          queue :default
          action :process_relationship
          action_input %{targets: [%{name: "default_name_from_input"}]}
          where expr(processed != true)
          scheduler_cron false

          worker_module_name __MODULE__.Worker.ProcessWithSharedContext

          scheduler_module_name __MODULE__.Scheduler.ProcessWithSharedContext
        end

        trigger :process_without_shared_context do
          queue :default
          action :process_relationship
          action_input %{targets: [%{name: "default_name_from_input"}]}
          where expr(processed != true)
          worker_read_action :read
          scheduler_cron false

          worker_module_name __MODULE__.Worker.ProcessWithoutSharedContext

          scheduler_module_name __MODULE__.Scheduler.ProcessWithoutSharedContext
        end
      end
    end

    policies do
      bypass AshOban.Checks.AshObanInteraction do
        authorize_if always()
      end

      policy always() do
        authorize_if always()
      end
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:name]
      end

      update :process_relationship do
        require_atomic? false
        accept []
        argument :targets, {:array, :map}

        change set_attribute(:processed, true)

        change manage_relationship(:targets, type: :create)
      end
    end

    mnesia do
      table :triggered
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :processed, :boolean, default: false, allow_nil?: false
      timestamps()
    end

    relationships do
      has_many :targets, AshOban.SharedContextTest.RelationshipTarget do
        public? true
        destination_attribute :triggered_with_relationship_id
      end
    end
  end

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([TestDomain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup_all do
    :mnesia.create_schema([node()])
    :mnesia.start()
    :ok
  end

  setup do
    try do
      :mnesia.delete_table(:triggered)
      :mnesia.delete_table(:target)
    catch
      :exit, {:aborted, {:no_exists, _}} -> :ok
    end

    :mnesia.create_table(:triggered, attributes: [:id, :val])
    :mnesia.create_table(:target, attributes: [:id, :val])
    :ok
  end

  describe "shared_context? feature" do
    test "shared_context?: true - trigger propagates context to nested manage_relationship" do
      parent =
        TriggeredWithRelationship
        |> Ash.Changeset.for_create(:create, %{name: "parent_with_shared"})
        |> Ash.create!()

      AshOban.run_trigger(parent, :process_with_shared_context,
        action_arguments: %{targets: [%{name: "child_target"}]}
      )

      assert %{success: 1} =
               Oban.drain_queue(queue: :default)

      parent = Ash.reload!(parent, authorize?: false)
      assert parent.processed

      assert [target] = Ash.load!(parent, :targets, authorize?: false).targets
      assert target.name == "child_target"
    end

    test "shared_context?: false - trigger does not propagate context, fails policy check" do
      parent =
        TriggeredWithRelationship
        |> Ash.Changeset.for_create(:create, %{name: "parent_without_shared"})
        |> Ash.create!()

      refute parent.processed

      assert_raise Ash.Error.Forbidden, fn ->
        ExUnit.CaptureLog.capture_log(fn ->
          Oban.Testing.with_testing_mode(:inline, fn ->
            AshOban.run_trigger(parent, :process_without_shared_context,
              action_arguments: %{targets: [%{name: "child_target"}]}
            )
          end)
        end)
      end

      parent = Ash.reload!(parent, authorize?: false)
      refute parent.processed

      assert [] == Ash.load!(parent, :targets, authorize?: false).targets
    end
  end
end
