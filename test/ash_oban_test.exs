defmodule AshObanTest do
  use ExUnit.Case
  doctest AshOban

  defmodule Api do
    use Ash.Api

    resources do
      allow_unregistered? true
    end
  end

  defmodule Triggered do
    use Ash.Resource,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        api Api

        trigger :process do
          action :process
          where expr(processed != true)
        end
      end
    end

    actions do
      defaults [:create]

      read :read do
        primary? true
        pagination keyset?: true
      end

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
