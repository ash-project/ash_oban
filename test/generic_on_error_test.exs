# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.GenericOnErrorTest do
  use ExUnit.Case, async: false

  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.GenericOnErrorTest.Ticket
    end
  end

  defmodule Ticket do
    use Ash.Resource,
      domain: AshOban.GenericOnErrorTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        trigger :charge do
          action :charge
          where expr(state == :open)
          on_error :mark_failed
          max_attempts 2
          log_errors? false
          log_final_error? false
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.Charge
          scheduler_module_name __MODULE__.Scheduler.Charge
        end

        trigger :charge_fails_job do
          action :charge
          where expr(state == :open)
          on_error :mark_failed
          on_error_fails_job? true
          max_attempts 1
          log_errors? false
          log_final_error? false
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.ChargeFailsJob
          scheduler_module_name __MODULE__.Scheduler.ChargeFailsJob
        end

        trigger :charge_without_on_error do
          action :charge
          where expr(state == :open)
          max_attempts 1
          log_errors? false
          log_final_error? false
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.ChargeWithoutOnError
          scheduler_module_name __MODULE__.Scheduler.ChargeWithoutOnError
        end
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :state, :atom, allow_nil?: false, default: :open, public?: true
    end

    actions do
      defaults [:read, create: []]

      update :pay do
        change set_attribute(:state, :paid)
      end

      action :charge do
        argument :primary_key, :map, allow_nil?: false

        run fn input, _context ->
          if Process.get(:pay_while_charging) do
            AshOban.GenericOnErrorTest.Ticket
            |> Ash.get!(input.arguments.primary_key["id"])
            |> Ash.Changeset.for_update(:pay)
            |> Ash.update!()
          end

          {:error, "the payment provider is down"}
        end
      end

      update :mark_failed do
        require_atomic? false
        argument :error, :term

        change fn changeset, _context ->
          send(self(), {:on_error, changeset.arguments.error})
          changeset
        end

        change set_attribute(:state, :failed)
      end
    end
  end

  setup_all do
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    Oban.delete_all_jobs(Oban.Job)
    on_exit(fn -> Process.delete(:pay_while_charging) end)
    :ok
  end

  test "runs `on_error` after the last attempt fails" do
    ticket = Ash.create!(Ticket, %{})

    AshOban.run_trigger(ticket, :charge)

    assert %{failure: 1} = Oban.drain_queue(queue: :default)
    refute_received {:on_error, _}
    assert Ash.reload!(ticket).state == :open

    assert %{success: 1} = Oban.drain_queue(queue: :default, with_scheduled: true)
    assert_received {:on_error, %Ash.Error.Unknown{}}
    assert Ash.reload!(ticket).state == :failed
  end

  test "fails the job after running `on_error` with `on_error_fails_job? true`" do
    ticket = Ash.create!(Ticket, %{})

    AshOban.run_trigger(ticket, :charge_fails_job)

    assert %{discard: 1} = Oban.drain_queue(queue: :default)
    assert_received {:on_error, _}
    assert Ash.reload!(ticket).state == :failed
  end

  test "cancels the job instead of running `on_error` when the record no longer matches the `where`" do
    ticket = Ash.create!(Ticket, %{})
    Process.put(:pay_while_charging, true)

    AshOban.run_trigger(ticket, :charge_fails_job)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :default)
    refute_received {:on_error, _}
    assert Ash.reload!(ticket).state == :paid
  end

  test "fails the job without `on_error`" do
    ticket = Ash.create!(Ticket, %{})

    AshOban.run_trigger(ticket, :charge_without_on_error)

    assert %{discard: 1} = Oban.drain_queue(queue: :default)
    assert Ash.reload!(ticket).state == :open
  end
end
