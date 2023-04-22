defmodule AshObanTest do
  use ExUnit.Case
  doctest AshOban

  defmodule Triggered do
    use Ash.Resource,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        trigger :process, expr(processed != true)
      end
    end

    actions do
      defaults [:read, :create]

      update :process do
        change set_attribute(:processed, true)
      end
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end
  end

  test "foo" do
    assert [%AshOban.Trigger{action: :process}] = AshOban.Info.oban_triggers(Triggered)
  end
end
