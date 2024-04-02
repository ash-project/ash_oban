defmodule AshObanTest do
  use ExUnit.Case, async: false
  doctest AshOban

  alias AshOban.Test.Api
  alias AshOban.Test.Triggered

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([Api], Application.get_env(:ash_oban, :oban)))

    :ok
  end

  setup do
    Enum.each(
      [:triggered_process, :triggered_process_2, :triggered_say_hello],
      &Oban.drain_queue(queue: &1)
    )
  end

  test "nothing happens if no records exist" do
    assert %{success: 1} = AshOban.Test.schedule_and_run_triggers(Triggered)
  end

  test "if a record exists, it is processed" do
    Triggered
    |> Ash.Changeset.for_create(:create, %{})
    |> Api.create!()

    assert %{success: 2} =
             AshOban.Test.schedule_and_run_triggers(Triggered,
               actor: %AshOban.Test.ActorPersister.FakeActor{id: 1}
             )
  end

  test "if an actor is not set, it is nil when executing the job" do
    Triggered
    |> Ash.Changeset.for_create(:create)
    |> Api.create!()

    assert %{success: 1, failure: 1} =
             AshOban.Test.schedule_and_run_triggers(Triggered)
  end

  test "dsl introspection" do
    assert [
             %AshOban.Trigger{action: :process},
             %AshOban.Trigger{action: :process, scheduler: nil}
           ] = AshOban.Info.oban_triggers(Triggered)
  end

  test "cron configuration" do
    config =
      AshOban.config([Api],
        plugins: [
          {Oban.Plugins.Cron, []}
        ],
        queues: [
          triggered_process: 10,
          triggered_process_2: 10,
          triggered_say_hello: 10
        ]
      )

    assert [
             plugins: [
               {Oban.Plugins.Cron,
                [
                  crontab: [
                    {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello, []},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.Process, []}
                  ]
                ]}
             ],
             queues: [
               triggered_process: 10,
               triggered_process_2: 10,
               triggered_say_hello: 10
             ]
           ] = config
  end

  test "oban pro configuration" do
    config =
      AshOban.config([Api], [
        engine: Oban.Pro.Engines.Smart,
        plugins: [
          {Oban.Pro.Plugins.DynamicCron, [
            timezone: "Europe/Rome",
            sync_mode: :automatic,
            crontab: []
          ]},
          {Oban.Pro.Plugins.DynamicQueues,
            queues: [
              triggered_process: 10,
              triggered_process_2: 10,
              triggered_say_hello: 10
            ]}
        ],
        queues: false
      ])

    assert [
              engine: Oban.Pro.Engines.Smart,
              plugins: [
                {Oban.Pro.Plugins.DynamicCron, [
                  timezone: "Europe/Rome",
                  sync_mode: :automatic,
                  crontab: [
                    {"0 0 1 1 *", AshOban.Test.Triggered.AshOban.ActionWorker.SayHello, []},
                    {"* * * * *", AshOban.Test.Triggered.AshOban.Scheduler.Process, []}
                  ]
                ]},
                {Oban.Pro.Plugins.DynamicQueues,
                queues: [
                  triggered_process: 10,
                  triggered_process_2: 10,
                  triggered_say_hello: 10
                ]}
              ],
              queues: false
            ] = config
    end
end
