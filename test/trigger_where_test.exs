# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.TriggerWhereTest do
  use ExUnit.Case, async: false

  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.TriggerWhereTest.Ticket
      resource AshOban.TriggerWhereTest.PostgresTicket
    end
  end

  # Runs the function set by a test while the trigger's action runs,
  # after the worker has read the record.
  defmodule DuringAction do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      run()
      changeset
    end

    @impl true
    def atomic(changeset, _opts, _context) do
      send(self(), :atomic)
      {:ok, changeset}
    end

    def run do
      case Process.get(__MODULE__) do
        nil -> :ok
        fun -> fun.()
      end
    end
  end

  # Runs the function set by a test inside the action's transaction, after the worker
  # has read the record again.
  defmodule InTransaction do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        case Process.get(__MODULE__) do
          nil -> :ok
          fun -> fun.()
        end

        changeset
      end)
    end
  end

  # Takes the ticket out of the trigger's `where` from inside the action itself.
  defmodule StartClosing do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        changeset.data |> Ash.Changeset.for_update(:start_closing) |> Ash.update!()
        changeset
      end)
    end
  end

  # Does the action's work, which takes the ticket out of the trigger's `where`,
  # before an action without a transaction writes the record.
  defmodule CloseBeforeTransaction do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context) do
      Ash.Changeset.before_transaction(changeset, fn changeset ->
        changeset.data |> Ash.Changeset.for_update(:mark_closed) |> Ash.update!()
        changeset
      end)
    end
  end

  defmodule NotAtomic do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _opts, _context), do: changeset

    @impl true
    def atomic(_changeset, _opts, _context), do: {:not_atomic, "not atomic"}
  end

  # Adds an `after_action` hook to the read, so it can't be used for an atomic bulk update,
  # and runs the function set by a test once the records have been read.
  defmodule ReadHook do
    use Ash.Resource.Preparation

    @impl true
    def prepare(query, _opts, _context) do
      Ash.Query.after_action(query, fn _query, records ->
        AshOban.TriggerWhereTest.DuringAction.run()
        {:ok, records}
      end)
    end
  end

  defmodule Ticket do
    use Ash.Resource,
      domain: AshOban.TriggerWhereTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        trigger :close_open_upgradable do
          action :close_upgradable
          where expr(state == :open)
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.CloseOpenUpgradable
          scheduler_module_name __MODULE__.Scheduler.CloseOpenUpgradable
        end

        trigger :close_open_atomic_batches do
          action :close_atomic
          where expr(state == :open)
          queue :default
          scheduler_cron false
          worker_read_action :read_with_hook
          worker_module_name __MODULE__.Worker.CloseOpenAtomicBatches
          scheduler_module_name __MODULE__.Scheduler.CloseOpenAtomicBatches
        end

        trigger :close_open_not_atomic do
          action :close_not_atomic
          where expr(state == :open)
          queue :default
          max_attempts 1
          log_final_error? false
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.CloseOpenNotAtomic
          scheduler_module_name __MODULE__.Scheduler.CloseOpenNotAtomic
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

      update :close_upgradable do
        require_atomic? false
        atomic_upgrade? true
        change AshOban.TriggerWhereTest.DuringAction
        change set_attribute(:state, :closed)
      end

      # No keyset pagination, so `:atomic_batches` has to stream it with a full read.
      read :read_with_hook do
        prepare AshOban.TriggerWhereTest.ReadHook
      end

      update :close_atomic do
        change set_attribute(:state, :closed)
      end

      update :close_not_atomic do
        change AshOban.TriggerWhereTest.NotAtomic
        change set_attribute(:state, :closed)
      end
    end
  end

  # Actions that can't be done atomically are protected by locking the record in their
  # transaction, so they're tested against a data layer that can lock.
  defmodule PostgresTicket do
    use Ash.Resource,
      domain: AshOban.TriggerWhereTest.Domain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshOban]

    postgres do
      table "trigger_where_tickets"
      repo(AshOban.Test.Repo)
    end

    oban do
      triggers do
        trigger :close_open do
          action :close
          where expr(state == :open)
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.CloseOpen
          scheduler_module_name __MODULE__.Scheduler.CloseOpen
        end

        trigger :close_open_in_steps do
          action :close_in_steps
          where expr(state == :open)
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.CloseOpenInSteps
          scheduler_module_name __MODULE__.Scheduler.CloseOpenInSteps
        end

        trigger :close_open_without_transaction do
          action :close_without_transaction
          where expr(state == :open)
          queue :default
          scheduler_cron false
          worker_read_action :read
          worker_module_name __MODULE__.Worker.CloseOpenWithoutTransaction
          scheduler_module_name __MODULE__.Scheduler.CloseOpenWithoutTransaction
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

      update :start_closing do
        change set_attribute(:state, :closing)
      end

      update :mark_closed do
        change set_attribute(:state, :closed)
      end

      update :close do
        require_atomic? false
        change AshOban.TriggerWhereTest.DuringAction
        change AshOban.TriggerWhereTest.InTransaction
        change set_attribute(:state, :closed)
      end

      update :close_in_steps do
        require_atomic? false
        change AshOban.TriggerWhereTest.StartClosing
        change set_attribute(:state, :closed)
      end

      update :close_without_transaction do
        require_atomic? false
        transaction? false
        accept []
        change AshOban.TriggerWhereTest.CloseBeforeTransaction
      end
    end
  end

  setup_all do
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    Oban.delete_all_jobs(Oban.Job)
    AshOban.Test.Repo.query!("DELETE FROM trigger_where_tickets")

    on_exit(fn ->
      Process.delete(DuringAction)
      Process.delete(InTransaction)
    end)

    :ok
  end

  defp pay_after_the_workers_read(ticket) do
    Process.put(DuringAction, fn ->
      Process.delete(DuringAction)
      ticket |> Ash.Changeset.for_update(:pay) |> Ash.update!()
    end)
  end

  for {resource, trigger} <- [
        {PostgresTicket, :close_open},
        {Ticket, :close_open_upgradable}
      ] do
    describe "#{trigger}" do
      test "runs the action when the record still matches the `where`" do
        ticket = Ash.create!(unquote(resource), %{})

        AshOban.run_trigger(ticket, unquote(trigger))

        assert %{success: 1} = Oban.drain_queue(queue: :default)
        assert Ash.reload!(ticket).state == :closed
      end

      test "cancels the job when the record stops matching the `where` after the worker's read" do
        ticket = Ash.create!(unquote(resource), %{})
        pay_after_the_workers_read(ticket)

        AshOban.run_trigger(ticket, unquote(trigger))

        assert %{cancelled: 1} = Oban.drain_queue(queue: :default)
        assert Ash.reload!(ticket).state == :paid
      end
    end
  end

  describe "actions that can't be done atomically" do
    test "lock the record while the action runs" do
      ticket = Ash.create!(PostgresTicket, %{})
      id = Ecto.UUID.dump!(ticket.id)
      test = self()

      # From another connection, which a spawned process gets, unlike a `Task`.
      Process.put(InTransaction, fn ->
        spawn(fn ->
          result =
            AshOban.Test.Repo.query(
              "SELECT id FROM trigger_where_tickets WHERE id = $1 FOR UPDATE NOWAIT",
              [id]
            )

          send(test, {:lock_attempt, result})
        end)

        assert_receive {:lock_attempt, result}
        send(test, {:lock_attempt, result})
      end)

      AshOban.run_trigger(ticket, :close_open)

      assert %{success: 1} = Oban.drain_queue(queue: :default)

      assert_received {:lock_attempt,
                       {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}}}
    end

    test "aren't cancelled by their own changes to the fields the `where` reads" do
      ticket = Ash.create!(PostgresTicket, %{})

      AshOban.run_trigger(ticket, :close_open_in_steps)

      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert Ash.reload!(ticket).state == :closed
    end

    test "without a transaction, aren't cancelled by work done before the record is written" do
      ticket = Ash.create!(PostgresTicket, %{})

      AshOban.run_trigger(ticket, :close_open_without_transaction)

      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert Ash.reload!(ticket).state == :closed
    end
  end

  describe "require_atomic? true actions" do
    test "use `:atomic_batches` when the worker's read action can't be used for `:atomic`" do
      ticket = Ash.create!(Ticket, %{})

      AshOban.run_trigger(ticket, :close_open_atomic_batches)

      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert Ash.reload!(ticket).state == :closed
    end

    test "check the `where` again with `:atomic_batches`" do
      ticket = Ash.create!(Ticket, %{})
      pay_after_the_workers_read(ticket)

      AshOban.run_trigger(ticket, :close_open_atomic_batches)

      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert Ash.reload!(ticket).state == :paid
    end

    test "never run non-atomically" do
      ticket = Ash.create!(Ticket, %{})

      AshOban.run_trigger(ticket, :close_open_not_atomic)

      assert %{success: 0} = Oban.drain_queue(queue: :default)
      assert Ash.reload!(ticket).state == :open
    end
  end

  test "an action that can be upgraded to an atomic one still is" do
    ticket = Ash.create!(Ticket, %{})

    AshOban.run_trigger(ticket, :close_open_upgradable)

    assert %{success: 1} = Oban.drain_queue(queue: :default)
    assert_received :atomic
  end
end
