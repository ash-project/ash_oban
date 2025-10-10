# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshObanTest do
  use ExUnit.Case, async: false
  doctest AshOban

  alias AshOban.Test.Domain
  alias AshOban.Test.DomainPro
  alias AshOban.Test.Triggered
  # alias AshOban.Test.TriggeredPro

  use Oban.Testing, repo: AshOban.Test.Repo, prefix: "private"

  require Ash.Query

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  describe "oban free tier" do
    setup [:ash_oban_pro]
    @describetag pro?: false

    setup do
      Enum.each(
        [
          :triggered_process,
          :triggered_process_2,
          :triggered_say_hello,
          :triggered_tenant_aware,
          :triggered_process_generic,
          :triggered_fail_oban_job
        ],
        &Oban.drain_queue(queue: &1)
      )
    end

    test "nothing happens if no records exist" do
      assert %{success: 7} = AshOban.Test.schedule_and_run_triggers(Triggered)
    end

    test "if a record exists, it is processed" do
      Triggered
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :process},
                 actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
               )
    end

    test "extra args are set on a job" do
      Triggered
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

      AshOban.schedule(Triggered, :process)

      assert [_scheduler] =
               all_enqueued(worker: Triggered.AshOban.Scheduler.Process)

      # run scheduler
      Oban.drain_queue(queue: :triggered_process)

      assert [job] =
               all_enqueued(worker: Triggered.AshOban.Worker.Process)

      assert job.args["extra_arg"] == 1
    end

    test "sort is applied when scheduling" do
      triggered1 =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      triggered2 =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      assert %{success: 3} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :process},
                 actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
               )

      triggered1 =
        Ash.reload!(triggered1)

      triggered2 =
        Ash.reload!(triggered2)

      assert DateTime.before?(triggered1.updated_at, triggered2.updated_at)
    end

    test "a record can be processed manually with additional arguments" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.run_trigger(record, :process,
        action_arguments: %{special_arg: "special_value"},
        actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
      )

      AshOban.Test.schedule_and_run_triggers(Triggered)

      assert_receive {:special_arg, "special_value"}
    end

    test "actions done atomically will be done atomically" do
      Triggered
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :process_atomically})

      assert Ash.read_first!(Triggered).processed
    end

    test "only jobs for the specified tenant are queued" do
      tenant_1 =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      tenant_2 =
        Triggered
        |> Ash.Changeset.for_create(:create, %{tenant_id: 2})
        |> Ash.create!()

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :tenant_aware})

      refute Ash.load!(tenant_1, :processed).processed
      assert Ash.load!(tenant_2, :processed).processed
    end

    test "on_error_fails_job? false will succeed the job" do
      model =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      assert %{success: 2, discard: 0} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :dont_fail_oban_job})

      assert Ash.load!(model, :processed).processed
    end

    test "on_error_fails_job? true will fail the job" do
      model =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      assert %{discard: 1, success: 1} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :fail_oban_job})

      assert Ash.load!(model, :processed).processed
    end

    test "on_error_fails_job? true with custom backoff will fail the job" do
      _model =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      # Im not sure how to properly test that backoff has been called
      assert %{failure: 1, success: 1} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :fail_oban_job_custom_backoff})
    end

    @tag :focus
    test "bulk create triggers after_batch change" do
      [
        %{number: 1},
        %{number: 2},
        %{number: 3},
        %{number: 4}
      ]
      |> Ash.bulk_create!(Triggered, :bulk_create)

      jobs =
        all_enqueued(worker: Triggered.AshOban.Worker.ProcessAtomically) |> Enum.sort_by(& &1.id)

      assert [1, 2, 3, 4] = Enum.map(jobs, &Map.get(&1.args, "number"))
    end

    test "if an actor is not set, it is nil when executing the job" do
      Triggered
      |> Ash.Changeset.for_create(:create)
      |> Ash.create!()

      assert %{success: 9, failure: 1} =
               AshOban.Test.schedule_and_run_triggers(Triggered)
    end

    test "if a tenant is converted with Ash.ToTenant" do
      tenant =
        Triggered
        |> Ash.Changeset.for_create(:create, %{tenant_id: 2})
        |> Ash.create!()

      tenant =
        Triggered
        |> Ash.Query.for_read(:read)
        |> Ash.read_one!(tenant: tenant)

      tenant
      |> Ash.Changeset.for_update(:update_triggered)
      |> Ash.update!()

      assert %{success: 10, failure: 0} =
               AshOban.Test.schedule_and_run_triggers(Triggered)
    end

    test "dsl introspection" do
      assert [
               %AshOban.Trigger{action: :process},
               %AshOban.Trigger{action: :process_atomically},
               %AshOban.Trigger{action: :process, scheduler: nil},
               %AshOban.Trigger{name: :process_generic},
               %AshOban.Trigger{name: :tenant_aware},
               %AshOban.Trigger{name: :fail_oban_job},
               %AshOban.Trigger{name: :dont_fail_oban_job},
               %AshOban.Trigger{name: :fail_oban_job_custom_backoff}
             ] = AshOban.Info.oban_triggers(Triggered)
    end

    test "cron configuration" do
      config =
        AshOban.config([Domain],
          plugins: [
            {Oban.Plugins.Cron, []}
          ],
          queues: [
            triggered_process: 10,
            triggered_process_2: 10,
            triggered_say_hello: 10,
            triggered_tenant_aware: 10,
            triggered_process_generic: 10,
            triggered_fail_oban_job: 10
          ]
        )

      assert [
               plugins: [
                 {Oban.Plugins.Cron,
                  [
                    crontab: [
                      {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello, []},
                      {"* * * * *",
                       AshOban.Test.Triggered.AshOban.Scheduler.FailObanJobWithCustomBackoff, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.DontFailObanJob, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.FailObanJob, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.TenantAware, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessGeneric, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessAtomically,
                       []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.Process, []}
                    ]
                  ]}
               ],
               queues: [
                 triggered_process: 10,
                 triggered_process_2: 10,
                 triggered_say_hello: 10,
                 triggered_tenant_aware: 10,
                 triggered_process_generic: 10,
                 triggered_fail_oban_job: 10
               ]
             ] = config
    end
  end

  describe "oban pro tier" do
    setup [:ash_oban_pro]

    setup do
      Enum.each(
        [
          :triggered_pro_process_with_state
        ],
        &Oban.drain_queue(queue: &1)
      )
    end

    @tag pro?: true
    test "if oban.pro true, puts `state` in crontab opts" do
      Oban.start_link(AshOban.config([DomainPro], Application.get_env(:ash_oban, :oban_pro)))

      config =
        AshOban.config([DomainPro],
          engine: Oban.Pro.Engines.Smart,
          plugins: [
            {Oban.Pro.Plugins.DynamicCron,
             [
               timezone: "Europe/Rome",
               sync_mode: :automatic,
               crontab: []
             ]},
            {Oban.Pro.Plugins.DynamicQueues,
             queues: [
               triggered_pro_process_with_state: 10
             ]}
          ],
          queues: false
        )

      assert [
               engine: Oban.Pro.Engines.Smart,
               plugins: [
                 {Oban.Pro.Plugins.DynamicCron,
                  [
                    timezone: "Europe/Rome",
                    sync_mode: :automatic,
                    crontab: [
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessWithState,
                       [paused: true]}
                    ]
                  ]},
                 {Oban.Pro.Plugins.DynamicQueues,
                  queues: [
                    triggered_pro_process_with_state: 10
                  ]}
               ],
               queues: false
             ] = config
    end

    @tag pro?: false
    test "if oban.pro is false, setting state on Plugins raises error message" do
      assert_raise(
        RuntimeError,
        "The `state` option on triggers and scheduled actions is only supported when using Oban Pro. Ignoring state :paused",
        fn ->
          Oban.start_link(AshOban.config([DomainPro], Application.get_env(:ash_oban, :oban_pro)))

          AshOban.config([DomainPro],
            engine: Oban.Pro.Engines.Smart,
            plugins: [
              {Oban.Pro.Plugins.DynamicCron,
               [
                 timezone: "Europe/Rome",
                 sync_mode: :automatic,
                 crontab: []
               ]},
              {Oban.Pro.Plugins.DynamicQueues,
               queues: [
                 triggered_pro_process_with_state: 10
               ]}
            ],
            queues: false
          )
        end
      )
    end
  end

  defp ash_oban_pro(%{pro?: true} = _context) do
    Application.put_env(:ash_oban, :pro?, true)
    on_exit(fn -> Application.put_env(:ash_oban, :pro?, false) end)
    :ok
  end

  defp ash_oban_pro(_context) do
    Application.put_env(:ash_oban, :pro?, false)
    :ok
  end
end
