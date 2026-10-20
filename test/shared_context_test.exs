# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.SharedContextTest do
  use ExUnit.Case, async: false

  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  require Ash.Query

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.SharedContextTest.RelationshipTarget
      resource AshOban.SharedContextTest.TriggeredWithRelationship
      resource AshOban.SharedContextTest.Guarded
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
      table :target
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
          shared_context :all
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

        # No shared_context, but the where reads a policy-protected aggregate.
        trigger :process_with_targets do
          queue :default
          action :process
          where expr(processed != true and target_count > 0)

          worker_module_name __MODULE__.Worker.ProcessWithTargets

          scheduler_module_name __MODULE__.Scheduler.ProcessWithTargets
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

      update :process do
        accept []
        change set_attribute(:processed, true)
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

    aggregates do
      count :target_count, :targets, public?: true
    end
  end

  defmodule Guarded do
    @moduledoc false
    use Ash.Resource,
      domain: AshOban.SharedContextTest.TestDomain,
      data_layer: Ash.DataLayer.Mnesia,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshOban]

    oban do
      triggers do
        trigger :process do
          queue :default
          action :process
          where expr(processed != true)
          worker_module_name __MODULE__.Worker.Process
          scheduler_module_name __MODULE__.Scheduler.Process
        end
      end
    end

    # No AshOban bypass, and a filter policy, so hidden records are quietly
    # left out of every read, the scheduler's included.
    policies do
      policy always() do
        authorize_if expr(visible == true)
      end
    end

    actions do
      defaults [:read, create: [:name, :visible]]

      update :process do
        accept []
        change set_attribute(:processed, true)
      end
    end

    mnesia do
      table :guarded
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :visible, :boolean, default: true, allow_nil?: false, public?: true
      attribute :processed, :boolean, default: false, allow_nil?: false, public?: true
    end
  end

  setup_all do
    Oban.start_link(AshOban.config([TestDomain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup_all do
    :mnesia.create_schema([node()])
    :mnesia.start()
    :ok
  end

  setup do
    for table <- [:triggered, :target, :guarded] do
      try do
        :mnesia.delete_table(table)
      catch
        :exit, {:aborted, {:no_exists, _}} -> :ok
      end

      :mnesia.create_table(table, attributes: [:id, :val])
    end

    :ok
  end

  describe "shared_context? feature" do
    test "shared_context?: true - trigger propagates context to nested manage_relationship" do
      parent =
        TriggeredWithRelationship
        |> Ash.Changeset.for_create(:create, %{name: "parent_with_shared"})
        |> Ash.create!()

      AshOban.Test.assert_would_schedule(parent, :process_with_shared_context)

      AshOban.run_trigger(parent, :process_with_shared_context,
        action_arguments: %{targets: [%{name: "child_target"}]}
      )

      assert_triggered(parent, :process_with_shared_context)

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

  # A trigger's `where` is evaluated by AshOban itself, so the AshOban bypass
  # must apply to the related data it reads, whatever `shared_context` says.
  describe "reads evaluating a trigger's where" do
    test "honor the bypass on related data in the scheduler" do
      with_target = parent_with_target()
      without_target = Ash.create!(TriggeredWithRelationship, %{name: "childless"})

      AshOban.Test.assert_would_schedule(with_target, :process_with_targets)
      AshOban.Test.refute_would_schedule(without_target, :process_with_targets)

      assert %{failure: 0} =
               AshOban.Test.schedule_and_run_triggers(
                 {TriggeredWithRelationship, :process_with_targets}
               )

      assert Ash.reload!(with_target, authorize?: false).processed
      refute Ash.reload!(without_target, authorize?: false).processed
    end

    test "honor the bypass on related data when the worker re-reads the record" do
      parent = parent_with_target()

      AshOban.run_trigger(parent, :process_with_targets)
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)

      assert Ash.reload!(parent, authorize?: false).processed
    end

    test "authorize the same way in would-schedule assertions as in the scheduler" do
      hidden = Ash.create!(Guarded, %{name: "hidden", visible: false}, authorize?: false)
      shown = Ash.create!(Guarded, %{name: "shown"}, authorize?: false)

      AshOban.Test.refute_would_schedule(hidden, :process)
      AshOban.Test.assert_would_schedule(shown, :process)

      AshOban.Test.schedule_and_run_triggers({Guarded, :process})
      refute Ash.reload!(hidden, authorize?: false).processed
      assert Ash.reload!(shown, authorize?: false).processed
    end
  end

  defp parent_with_target do
    parent = Ash.create!(TriggeredWithRelationship, %{name: "parent"})

    Ash.create!(RelationshipTarget, %{name: "target", triggered_with_relationship_id: parent.id},
      authorize?: false
    )

    parent
  end
end
