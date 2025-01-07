defmodule AshObanTest do
  use ExUnit.Case, async: false
  doctest AshOban

  alias AshOban.Test.Domain
  alias AshOban.Test.Triggered

  use Oban.Testing, repo: AshOban.Test.Repo, prefix: "private"

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))

    :ok
  end

  setup do
    Enum.each(
      [
        :triggered_process,
        :triggered_process_2,
        :triggered_say_hello,
        :triggered_process_generic
      ],
      &Oban.drain_queue(queue: &1)
    )
  end

  test "nothing happens if no records exist" do
    assert %{success: 3} = AshOban.Test.schedule_and_run_triggers(Triggered)
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

  @tag :focus
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

  test "if an actor is not set, it is nil when executing the job" do
    Triggered
    |> Ash.Changeset.for_create(:create)
    |> Ash.create!()

    assert %{success: 5, failure: 1} =
             AshOban.Test.schedule_and_run_triggers(Triggered)
  end

  test "dsl introspection" do
    assert [
             %AshOban.Trigger{action: :process},
             %AshOban.Trigger{action: :process_atomically},
             %AshOban.Trigger{action: :process, scheduler: nil},
             %AshOban.Trigger{name: :process_generic}
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
          triggered_process_generic: 10
        ]
      )

    assert [
             plugins: [
               {Oban.Plugins.Cron,
                [
                  crontab: [
                    {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello, []},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessGeneric, []},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessAtomically, []},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.Process, []}
                  ]
                ]}
             ],
             queues: [
               triggered_process: 10,
               triggered_process_2: 10,
               triggered_say_hello: 10,
               triggered_process_generic: 10
             ]
           ] = config
  end

  test "oban pro configuration" do
    config =
      AshOban.config([Domain],
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
             triggered_process: 10,
             triggered_process_2: 10,
             triggered_say_hello: 10,
             triggered_process_generic: 10
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
                    {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello,
                     [paused: false]},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessGeneric,
                     [paused: false]},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.ProcessAtomically,
                     [paused: false]},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.Process,
                     [paused: false]}
                  ]
                ]},
               {Oban.Pro.Plugins.DynamicQueues,
                queues: [
                  triggered_process: 10,
                  triggered_process_2: 10,
                  triggered_say_hello: 10,
                  triggered_process_generic: 10
                ]}
             ],
             queues: false
           ] = config
  end
end
