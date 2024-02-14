defmodule AshObanTest do
  use ExUnit.Case
  doctest AshOban

  alias AshOban.Test.Api
  alias AshOban.Test.Triggered

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
end
