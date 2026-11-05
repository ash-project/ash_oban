# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ActorPersisterTest.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.ActorPersisterTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshOban]

  multitenancy do
    strategy :attribute
    attribute :tenant_id
  end

  oban do
    list_tenants [1, 2]

    triggers do
      trigger :process do
        action :process
        where expr(processed != true)
        queue :default
        actor_persister AshOban.Test.TenantActorPersister
        worker_module_name __MODULE__.AshOban.Worker.Process
        scheduler_module_name __MODULE__.AshOban.Scheduler.Process
      end
    end
  end

  actions do
    defaults [:read, create: [:tenant_id]]

    update :process do
      require_atomic? false
      change set_attribute(:processed, true)

      change fn changeset, context ->
        send(self(), {:processed_by, context.actor})
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
    attribute :tenant_id, :integer, allow_nil?: false
    timestamps()
  end
end

defmodule AshOban.ActorPersisterTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshOban.ActorPersisterTest.Post
  end
end

defmodule AshOban.ActorPersisterTest do
  use ExUnit.Case, async: false

  use Oban.Testing, repo: AshOban.Test.Repo, prefix: "private"

  alias AshOban.ActorPersisterTest.{Domain, Post}
  alias AshOban.Test.ActorPersister.FakeActor
  alias AshOban.Test.TenantActorPersister

  setup_all do
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    on_exit(fn ->
      AshOban.Test.Repo.delete_all(Oban.Job, prefix: "private")
    end)
  end

  describe "a persister with lookup/2" do
    test "receives the tenant the job runs in and the job" do
      post = Ash.create!(Post, %{tenant_id: 1}, tenant: 1)

      AshOban.run_trigger(post, :process, actor: %FakeActor{id: "member"}, tenant: 1)

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      worker = inspect(Post.AshOban.Worker.Process)

      assert_received {:lookup, %{"id" => "member"},
                       %{tenant: 1, job: %Oban.Job{worker: ^worker, args: %{"tenant" => 1}}}}

      assert_received {:processed_by, %FakeActor{id: "member"}}
      assert Ash.reload!(post, tenant: 1).processed
    end

    test "can stop a job from acting for an actor that no longer belongs to its tenant" do
      post = Ash.create!(Post, %{tenant_id: 1}, tenant: 1)

      AshOban.run_trigger(post, :process, actor: %FakeActor{id: "outsider"}, tenant: 1)

      assert %{cancelled: 1} = Oban.drain_queue(queue: :default)

      assert_received {:lookup, %{"id" => "outsider"}, %{tenant: 1}}
      refute_received {:processed_by, _}
      refute Ash.reload!(post, tenant: 1).processed
    end

    test "receives each tenant the scheduler reads in" do
      Ash.create!(Post, %{tenant_id: 1}, tenant: 1)
      Ash.create!(Post, %{tenant_id: 2}, tenant: 2)

      assert %{success: 3} =
               AshOban.Test.schedule_and_run_triggers({Post, :process},
                 actor: %FakeActor{id: "member"}
               )

      scheduler = inspect(Post.AshOban.Scheduler.Process)

      assert_received {:lookup, %{"id" => "member"},
                       %{tenant: 1, job: %Oban.Job{worker: ^scheduler}}}

      assert_received {:lookup, %{"id" => "member"},
                       %{tenant: 2, job: %Oban.Job{worker: ^scheduler}}}
    end
  end

  describe "lookup_actor/4" do
    test "fills in context keys that weren't given" do
      assert {:ok, %FakeActor{id: "member"}} =
               AshOban.lookup_actor(%{"id" => "member"}, TenantActorPersister, nil, %{tenant: 2})

      assert_received {:lookup, %{"id" => "member"}, %{tenant: 2, job: nil}}
    end

    test "returns the persister's error" do
      assert {:error, %AshOban.Errors.CancelJob{reason: :actor_not_in_tenant}} =
               AshOban.lookup_actor(%{"id" => "member"}, TenantActorPersister, nil, %{tenant: 3})
    end

    test "calls lookup/1 on a persister without lookup/2" do
      assert {:ok, %FakeActor{id: 1}} =
               AshOban.lookup_actor(%{"id" => 1}, AshOban.Test.ActorPersister, nil, %{tenant: 1})
    end
  end

  test "using AshOban.ActorPersister without a lookup callback warns" do
    warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule AshOban.ActorPersisterTest.NoLookup do
          use AshOban.ActorPersister
          def store(actor), do: actor
        end
        """)
      end)

    assert warning =~ "defines neither lookup/1 nor lookup/2"
  end
end
