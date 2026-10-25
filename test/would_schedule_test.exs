# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.WouldScheduleTest do
  use ExUnit.Case, async: false

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.WouldScheduleTest.Ticket
    end
  end

  defmodule Ticket do
    @moduledoc false
    use Ash.Resource,
      domain: AshOban.WouldScheduleTest.Domain,
      data_layer: Ash.DataLayer.Mnesia,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshOban]

    oban do
      triggers do
        trigger :process do
          queue :default
          action :process
          where expr(processed != true)
          scheduler_cron false
          default_actor(%AshOban.Test.ActorPersister.FakeActor{id: 1})
          worker_module_name __MODULE__.Worker.Process
          scheduler_module_name __MODULE__.Scheduler.Process
        end
      end
    end

    # Only an actor can see tickets, so reading without the trigger's actor finds nothing.
    policies do
      policy always() do
        authorize_if actor_present()
      end
    end

    actions do
      defaults [:read, create: []]

      update :process do
        accept []
        change set_attribute(:processed, true)
      end
    end

    mnesia do
      table :would_schedule_ticket
    end

    attributes do
      uuid_primary_key :id
      attribute :processed, :boolean, default: false, allow_nil?: false, public?: true
    end
  end

  setup_all do
    :mnesia.create_schema([node()])
    :mnesia.start()
    :ok
  end

  setup do
    try do
      :mnesia.delete_table(:would_schedule_ticket)
    catch
      :exit, {:aborted, {:no_exists, _}} -> :ok
    end

    :mnesia.create_table(:would_schedule_ticket, attributes: [:id, :val])

    :ok
  end

  defp create_ticket! do
    Ticket
    |> Ash.Changeset.for_create(:create, %{}, authorize?: false)
    |> Ash.create!()
  end

  test "assert_would_schedule reads as the trigger's actor by default" do
    ticket = create_ticket!()

    assert %Ticket{} = AshOban.Test.assert_would_schedule(ticket, :process)
  end

  test "refute_would_schedule reads as the trigger's actor by default" do
    ticket = create_ticket!()

    assert_raise ExUnit.AssertionError, fn ->
      AshOban.Test.refute_would_schedule(ticket, :process)
    end
  end

  test "an explicit actor is used instead of the trigger's actor" do
    ticket = create_ticket!()

    assert_raise Ash.Error.Forbidden, fn ->
      AshOban.Test.assert_would_schedule(ticket, :process, actor: nil)
    end
  end
end
