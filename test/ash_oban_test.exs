defmodule AshObanTest do
  use ExUnit.Case
  doctest AshOban

  alias AshOban.Test.Api
  alias AshOban.Test.Triggered

  test "foo" do
    assert [
             %AshOban.Trigger{action: :process},
             %AshOban.Trigger{action: :process, scheduler: nil}
           ] = AshOban.Info.oban_triggers(Triggered)
  end
end
