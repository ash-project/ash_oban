# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshObanTest do
  use ExUnit.Case, async: false
  doctest AshOban

  alias AshOban.Test.Domain
  alias AshOban.Test.DomainPro
  alias AshOban.Test.Triggered

  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  describe "oban free tier" do
    setup [:ash_oban_pro]
    @describetag pro?: false

    setup do
      Oban.delete_all_jobs(Oban.Job)

      :ok
    end

    test "all triggers has a default `stream_with` attribute" do
      assert [
               %AshOban.Trigger{action: :process, stream_with: :keyset},
               %AshOban.Trigger{action: :process_atomically, stream_with: :keyset},
               %AshOban.Trigger{action: :process, scheduler: nil, stream_with: :keyset},
               %AshOban.Trigger{name: :process_generic, stream_with: :keyset},
               %AshOban.Trigger{name: :tenant_aware, stream_with: :keyset},
               %AshOban.Trigger{name: :fail_oban_job, stream_with: :keyset},
               %AshOban.Trigger{name: :dont_fail_oban_job, stream_with: :keyset},
               %AshOban.Trigger{name: :fail_oban_job_custom_backoff, stream_with: :keyset},
               %AshOban.Trigger{name: :snooze_oban_job, stream_with: :keyset},
               %AshOban.Trigger{name: :cancel_oban_job, stream_with: :keyset},
               %AshOban.Trigger{name: :process_with_default_actor, stream_with: :keyset},
               %AshOban.Trigger{name: :scheduler_default_actor, stream_with: :keyset}
             ] = AshOban.Info.oban_triggers(Triggered)
    end

    test "worker and scheduler jobs use their configured priorities" do
      assert %{changes: %{priority: 1}} = Triggered.AshOban.Worker.Process.new(%{})
      assert %{changes: %{priority: 0}} = Triggered.AshOban.Scheduler.Process.new(%{})
    end

    test "user-supplied :args cannot override reserved job keys" do
      own =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      victim =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      malicious = %{
        "primary_key" => %{"id" => victim.id},
        "tenant" => "some_other_tenant",
        "action_arguments" => %{"injected" => true},
        "actor" => %{"id" => "someone_else"},
        "uniqueness_key" => "kept"
      }

      args =
        own
        |> AshOban.build_trigger(:process, args: malicious)
        |> Ecto.Changeset.get_field(:args)

      refute Map.has_key?(args, "primary_key")
      refute Map.has_key?(args, "tenant")
      refute Map.has_key?(args, "action_arguments")
      refute Map.has_key?(args, "actor")

      assert args[:primary_key] == %{id: own.id}
      assert args[:action_arguments] == %{}
      assert args["uniqueness_key"] == "kept"
      assert args[:extra_arg] == 1
    end

    test "nothing happens if no records exist" do
      assert %{success: 8} = AshOban.Test.schedule_and_run_triggers(Triggered)
    end

    test "if a record exists, it is processed" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.Test.assert_would_schedule(record, :process)

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :process},
                 actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
               )

      AshOban.Test.refute_would_schedule(Ash.reload!(record), :process)
    end

    test "extra args are set on a job" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.Test.assert_would_schedule(record, :process)

      AshOban.schedule(Triggered, :process)

      assert [_scheduler] =
               all_enqueued(worker: Triggered.AshOban.Scheduler.Process)

      # run scheduler
      Oban.drain_queue(queue: :triggered_process)

      [job] = AshOban.Test.assert_triggered(record, :process)
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
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.Test.assert_would_schedule(record, :process_atomically)

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :process_atomically})

      assert Ash.read_first!(Triggered).processed
      AshOban.Test.refute_would_schedule(Ash.reload!(record), :process_atomically)
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
      %{records: records} =
        [
          %{number: 1},
          %{number: 2},
          %{number: 3},
          %{number: 4}
        ]
        |> Ash.bulk_create!(Triggered, :bulk_create, return_records?: true)

      for record <- records do
        AshOban.Test.assert_triggered(record, :process_atomically)
      end

      jobs =
        all_enqueued(worker: Triggered.AshOban.Worker.ProcessAtomically) |> Enum.sort_by(& &1.id)

      assert [1, 2, 3, 4] = Enum.map(jobs, &Map.get(&1.args, "number"))
    end

    test "if an actor is not set, it is nil when executing the job" do
      Triggered
      |> Ash.Changeset.for_create(:create)
      |> Ash.create!()

      assert %{success: 10, failure: 1} =
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

      assert %{success: 11, failure: 0} =
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
               %AshOban.Trigger{name: :fail_oban_job_custom_backoff},
               %AshOban.Trigger{name: :snooze_oban_job},
               %AshOban.Trigger{name: :cancel_oban_job},
               %AshOban.Trigger{name: :process_with_default_actor},
               %AshOban.Trigger{name: :scheduler_default_actor}
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
            triggered_fail_oban_job: 10,
            triggered_notify_each_tenant: 10,
            triggered_snooze_oban_job: 10,
            triggered_cancel_oban_job: 10
          ]
        )

      assert [
               plugins: [
                 {Oban.Plugins.Cron,
                  [
                    crontab: [
                      {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SendStaticActor,
                       []},
                      {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.NotifyEachTenant,
                       []},
                      {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello, []},
                      {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.SchedulerStaticActor,
                       []},
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
                 triggered_fail_oban_job: 10,
                 triggered_notify_each_tenant: 10,
                 triggered_snooze_oban_job: 10,
                 triggered_cancel_oban_job: 10
               ]
             ] = config
    end

    test "scheduled action with multiple list_tenants dispatches per-tenant jobs" do
      AshOban.Test.schedule_and_run_triggers({Triggered, :notify_each_tenant},
        scheduled_actions?: true
      )

      assert_receive {:tenant, 1}
      assert_receive {:tenant, 2}
      assert_receive {:tenant, 3}
    end

    test "scheduled action with single tenant runs directly without dispatching" do
      AshOban.Test.schedule_and_run_triggers({Triggered, :say_hello},
        scheduled_actions?: true
      )

      refute_receive {:tenant, _}
    end

    test "disabling peer mode when plugins are disabled" do
      config = AshOban.config([Domain], [plugins: []], require?: false)
      assert config[:peer] == false
      assert config[:plugins] == []

      config = AshOban.config([Domain], [plugins: false], require?: false)
      assert config[:peer] == false
      assert config[:plugins] == []
    end

    test "raising SnoozeJob from an action snoozes the oban job" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.run_trigger(record, :snooze_oban_job)

      AshOban.Test.assert_triggered(record, :snooze_oban_job)

      assert %{snoozed: 1} = Oban.drain_queue(queue: :triggered_snooze_oban_job)
    end

    test "raising CancelJob from an action cancels the oban job" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.run_trigger(record, :cancel_oban_job)

      AshOban.Test.assert_triggered(record, :cancel_oban_job)

      assert %{cancelled: 1} = Oban.drain_queue(queue: :triggered_cancel_oban_job)
    end

    test "trigger with default_actor uses it when no actor is supplied (no persister required)" do
      record =
        Triggered
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      AshOban.run_trigger(record, :process_with_default_actor)

      assert %{success: 1} = Oban.drain_queue(queue: :triggered_process)

      assert_receive {:actor, %AshOban.Test.ActorPersister.FakeActor{id: 99}}
    end

    test "scheduled action with default_actor uses it when no actor is supplied (no persister required)" do
      AshOban.Test.schedule_and_run_triggers({Triggered, :send_default_actor},
        scheduled_actions?: true
      )

      assert_receive {:actor, %AshOban.Test.ActorPersister.FakeActor{id: 77}}
    end

    test "scheduler-fired trigger uses default_actor for record stream and worker action" do
      Triggered
      |> Ash.Changeset.for_create(:create, %{number: 999})
      |> Ash.create!()

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :scheduler_default_actor})

      assert_receive {:actor, %AshOban.Test.ActorPersister.FakeActor{id: 42}}
    end

    test "explicit actor in schedule_and_run_triggers overrides default_actor" do
      Triggered
      |> Ash.Changeset.for_create(:create, %{number: 999})
      |> Ash.create!()

      assert %{success: 2} =
               AshOban.Test.schedule_and_run_triggers({Triggered, :scheduler_default_actor},
                 actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
               )

      assert_receive {:actor, %AshOban.Test.ActorPersister.FakeActor{id: 1}}
    end

    test "lookup_actor falls back to default_actor when persister returns {:ok, nil}" do
      assert {:ok, %AshOban.Test.ActorPersister.FakeActor{id: 5}} =
               AshOban.lookup_actor(
                 nil,
                 AshOban.Test.ActorPersister,
                 %AshOban.Test.ActorPersister.FakeActor{id: 5}
               )
    end

    test "lookup_actor returns persister-resolved actor when stored, ignoring default_actor" do
      stored = AshOban.Test.ActorPersister.store(%AshOban.Test.ActorPersister.FakeActor{id: 1})

      assert {:ok, %AshOban.Test.ActorPersister.FakeActor{id: 1}} =
               AshOban.lookup_actor(
                 stored,
                 AshOban.Test.ActorPersister,
                 %AshOban.Test.ActorPersister.FakeActor{id: 99}
               )
    end

    test "lookup_actor returns default_actor when no persister is configured" do
      assert {:ok, %AshOban.Test.ActorPersister.FakeActor{id: 5}} =
               AshOban.lookup_actor(nil, :none, %AshOban.Test.ActorPersister.FakeActor{id: 5})
    end
  end

  describe "oban pro tier" do
    setup [:ash_oban_pro]

    setup do
      Oban.delete_all_jobs(Oban.Job)

      :ok
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
               engine: Oban.Pro.Engines.Smart,
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

  test "accepts the renamed Oban.Cron module in place of Oban.Plugins.Cron" do
    config =
      AshOban.config([Domain],
        plugins: [{Oban.Cron, []}],
        queues: [
          triggered_process: 10,
          triggered_process_2: 10,
          triggered_say_hello: 10,
          triggered_tenant_aware: 10,
          triggered_process_generic: 10,
          triggered_fail_oban_job: 10,
          triggered_notify_each_tenant: 10,
          triggered_snooze_oban_job: 10,
          triggered_cancel_oban_job: 10
        ]
      )

    assert [{Oban.Cron, cron_opts}] = config[:plugins]
    assert [_ | _] = cron_opts[:crontab]
  end

  test "accepts cron configured through the top-level `:cron` key" do
    for cron <- [[crontab: []], Oban.Cron, {Oban.Cron, crontab: []}] do
      config =
        AshOban.config([Domain],
          cron: cron,
          queues: [
            triggered_process: 10,
            triggered_process_2: 10,
            triggered_say_hello: 10,
            triggered_tenant_aware: 10,
            triggered_process_generic: 10,
            triggered_fail_oban_job: 10,
            triggered_notify_each_tenant: 10,
            triggered_snooze_oban_job: 10,
            triggered_cancel_oban_job: 10
          ]
        )

      refute config[:peer] == false

      crontab =
        case config[:cron] do
          {_module, cron_opts} -> cron_opts[:crontab]
          cron_opts -> cron_opts[:crontab]
        end

      assert [_ | _] = crontab
      assert Enum.all?(crontab, &match?({_cron, _worker, _opts}, &1))
    end
  end

  test "raises when cron is disabled via the top-level `:cron` key but triggers need scheduling" do
    assert_raise RuntimeError, ~r/Must configure cron/, fn ->
      AshOban.config([Domain],
        cron: false,
        queues: [
          triggered_process: 10,
          triggered_process_2: 10,
          triggered_say_hello: 10,
          triggered_tenant_aware: 10,
          triggered_process_generic: 10,
          triggered_fail_oban_job: 10,
          triggered_notify_each_tenant: 10,
          triggered_snooze_oban_job: 10,
          triggered_cancel_oban_job: 10
        ]
      )
    end
  end

  test "top-level plugin services preserve peer leadership" do
    config = AshOban.config([], [pruner: []], require?: false)

    refute config[:peer] == false
    assert config[:plugins] == []
  end

  test "top-level services remain disabled when plugins are disabled" do
    config =
      AshOban.config(
        [Domain],
        [plugins: false, cron: [crontab: []], pruner: []],
        require?: false
      )

    assert config[:peer] == false
    assert config[:plugins] == []
    refute Keyword.has_key?(config, :cron)
    refute Keyword.has_key?(config, :pruner)
  end

  if Code.ensure_loaded?(Oban.Pro.Cron) and Code.ensure_loaded?(Oban.Pro.Queues) do
    test "accepts cron configured through the top-level `:cron` key as a `{module, opts}` tuple" do
      config =
        AshOban.config([Domain],
          cron: {Oban.Pro.Cron, crontab: []},
          engine: Oban.Pro.Engine,
          queues: [
            triggered_process: 10,
            triggered_process_2: 10,
            triggered_say_hello: 10,
            triggered_tenant_aware: 10,
            triggered_process_generic: 10,
            triggered_fail_oban_job: 10,
            triggered_notify_each_tenant: 10,
            triggered_snooze_oban_job: 10,
            triggered_cancel_oban_job: 10
          ]
        )

      assert {Oban.Pro.Cron, cron_opts} = config[:cron]
      assert [_ | _] = cron_opts[:crontab]
    end

    test "accepts the renamed Oban.Pro.Engine and Oban.Pro.Cron together" do
      assert AshOban.config([], engine: Oban.Pro.Engine, plugins: [{Oban.Pro.Cron, []}])
    end

    test "raises when the renamed Oban.Pro.Cron plugin is used without a pro engine" do
      assert_raise RuntimeError, ~r/Expected oban engine to be one of/, fn ->
        AshOban.config([], engine: Oban.Engines.Basic, plugins: [{Oban.Pro.Cron, []}])
      end
    end

    test "raises when the renamed Oban.Pro.Queues plugin is used without a pro engine" do
      assert_raise RuntimeError, ~r/Expected oban engine to be one of/, fn ->
        AshOban.config([], engine: Oban.Engines.Basic, plugins: [{Oban.Pro.Queues, queues: []}])
      end
    end

    test "accepts queues configured through the unified top-level `:queues` key" do
      config =
        AshOban.config([Domain],
          engine: Oban.Pro.Engine,
          cron: [crontab: []],
          queues:
            {Oban.Pro.Queues,
             queues: [
               triggered_process: 10,
               triggered_process_2: 10,
               triggered_say_hello: 10,
               triggered_tenant_aware: 10,
               triggered_process_generic: 10,
               triggered_fail_oban_job: 10,
               triggered_notify_each_tenant: 10,
               triggered_snooze_oban_job: 10,
               triggered_cancel_oban_job: 10
             ]}
        )

      assert {Oban.Pro.Queues, queue_opts} = config[:queues]
      assert queue_opts[:queues][:triggered_process] == 10
      assert [_ | _] = config[:cron][:crontab]
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
