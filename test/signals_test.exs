# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.SignalsTest do
  use ExUnit.Case, async: false
  use AshOban.Test, repo: AshOban.Test.Repo, prefix: "private"

  alias AshOban.Test.ActorPersister.FakeActor
  alias AshOban.Test.{Domain, Order, SignalReceipt, Signals}

  setup_all do
    AshOban.Test.Repo.start_link()
    Oban.start_link(AshOban.config([Domain], Application.get_env(:ash_oban, :oban)))
    :ok
  end

  setup do
    Oban.delete_all_jobs(Oban.Job)
    :ok
  end

  defp receipts(order_id) do
    SignalReceipt
    |> Ash.read!()
    |> Enum.filter(&(&1.order_id == order_id))
  end

  defp jobs, do: all_enqueued(worker: AshOban.Signals.Worker, queue: :signals)

  defp insert_job(listener, signal, payload) do
    %{
      "signal_module" => "Elixir.AshOban.Test.Signals",
      "signal" => signal,
      "resource" => "Elixir.AshOban.Test.SignalReceipt",
      "listener" => listener,
      "payload" => payload
    }
    |> AshOban.Signals.Worker.new(queue: :signals)
    |> Oban.insert!()
  end

  test "emitting inserts a job for each listener that uses it, which runs the listener" do
    order = Ash.create!(Order, %{note: "hello"}, action: :place)
    order_id = order.id

    # the inline listener already ran
    assert_received {:notified_inline, %Signals.OrderPlaced{order_id: ^order_id}}

    assert [_, _] = jobs()
    assert receipts(order_id) == []

    assert %{success: 2} = Oban.drain_queue(queue: :signals)

    assert [%{note: "hello"}] = receipts(order_id)
    assert_received {:notified, %Signals.OrderPlaced{order_id: ^order_id}, nil, nil}
  end

  test "listeners run with the emitting action's actor and tenant" do
    order =
      Ash.create!(Order, %{}, action: :place, actor: %FakeActor{id: "zach"}, tenant: "acme")

    order_id = order.id

    assert %{success: 2} = Oban.drain_queue(queue: :signals)

    assert [%{actor_id: "zach"}] = receipts(order_id)
    assert_received {:notified, %{order_id: ^order_id}, %FakeActor{id: "zach"}, "acme"}
  end

  test "jobs are unique by signal_id, so emitting a signal again doesn't insert a second job" do
    signal_id = Ash.UUIDv7.generate()

    Ash.create!(Order, %{signal_id: signal_id}, action: :place_again)
    Ash.create!(Order, %{signal_id: signal_id}, action: :place_again)

    assert [_, _] = jobs()
  end

  test "jobs can be unique by signal fields" do
    order_id = Ash.UUID.generate()

    Ash.create!(Order, %{order_id: order_id}, action: :place_unique)
    Ash.create!(Order, %{order_id: order_id}, action: :place_unique)

    assert [%{args: %{"unique" => %{"order_id" => ^order_id}}}] = jobs()
  end

  test "a batch listener gets a job for each signal, and runs with one signal without chunks" do
    Ash.bulk_create!([%{}, %{}], Order, :place_batched)

    assert [%{args: %{"payload" => %{}}}, %{args: %{"payload" => %{}}}] = jobs()
    assert %{success: 2} = Oban.drain_queue(queue: :signals)
    assert_received {:notified_all, [%Signals.OrdersBatched{}]}
    assert_received {:notified_all, [%Signals.OrdersBatched{}]}
  end

  test "AshOban.config requires the queues of signal listeners" do
    config = Application.get_env(:ash_oban, :oban)

    assert AshOban.config([AshOban.Test.SignalsDomain], config)

    assert_raise RuntimeError,
                 ~r/Must configure the queue `:signals`, required for\nthe signal listener `:notify` on AshOban.Test.QueuedSignalListener/,
                 fn ->
                   AshOban.config(
                     [AshOban.Test.SignalsDomain],
                     Keyword.update!(config, :queues, &Keyword.delete(&1, :signals))
                   )
                 end
  end

  describe "stored signals" do
    test "fields the signal no longer has are ignored" do
      order_id = Ash.UUID.generate()

      insert_job("record", "order_placed", %{
        "signal_id" => Ash.UUIDv7.generate(),
        "order_id" => order_id,
        "removed" => "value"
      })

      assert %{success: 1} = Oban.drain_queue(queue: :signals)
      assert [_] = receipts(order_id)
    end

    test "a missing required field fails the job" do
      insert_job("record", "order_placed", %{
        "signal_id" => Ash.UUIDv7.generate(),
        "renamed_order_id" => Ash.UUID.generate()
      })

      assert %{failure: 1} = Oban.drain_queue(queue: :signals)
    end

    test "are upgraded by the listener's upgrader before they are loaded" do
      order_id = Ash.UUID.generate()

      insert_job("record_renamed", "order_renamed", %{
        "signal_id" => Ash.UUIDv7.generate(),
        "old_order_id" => order_id
      })

      assert %{success: 1} = Oban.drain_queue(queue: :signals)
      assert [_] = receipts(order_id)
    end

    test "a job for a listener that no longer exists fails" do
      insert_job("removed", "order_placed", %{
        "signal_id" => Ash.UUIDv7.generate(),
        "order_id" => Ash.UUID.generate()
      })

      assert %{failure: 1} = Oban.drain_queue(queue: :signals)
    end

    test "a job for a listener that now listens to a different signal fails" do
      insert_job("record", "orders_batched", %{
        "signal_id" => Ash.UUIDv7.generate(),
        "order_id" => Ash.UUID.generate()
      })

      assert %{failure: 1} = Oban.drain_queue(queue: :signals)
    end
  end

  describe "verification" do
    # Verification happens outside the test process, so verifier errors are emitted as warnings.
    defp compile_listener(on, use_opts \\ "") do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule AshOban.SignalsTest.Listener#{System.unique_integer([:positive])} do
          use Ash.Resource, domain: AshOban.Test.Domain#{use_opts}

          signals_in do
            from AshOban.Test.Signals do
              #{on}
            end
          end

          actions do
            action :notify do
              argument :signal, AshOban.Test.Signals.Verified, allow_nil?: false
              run fn _, _ -> :ok end
            end
          end
        end
        """)
      end)
    end

    test "options are validated" do
      assert compile_listener(
               ~s|on :verified, :notify, delivery: {AshOban.Signals, queue: "orders"}|
             ) =~
               "invalid value for :queue option"
    end

    test "unique keys must be fields of the signal" do
      assert compile_listener(
               "on :verified, :notify, delivery: {AshOban.Signals, unique: [keys: [:order_id, :signal_id]]}"
             ) == ""

      assert compile_listener(
               "on :verified, :notify, delivery: {AshOban.Signals, unique: [keys: [:customer_id]]}"
             ) =~ "`unique` refers to `:customer_id`, which is not a field of the signal."
    end

    if AshOban.Info.pro?() do
      test "chunks require the AshOban extension on the resource" do
        assert compile_listener("on :verified, :notify, delivery: {AshOban.Signals, chunks: []}") =~
                 "`chunks` requires the `AshOban` extension on the resource"

        assert compile_listener(
                 "on :verified, :notify, delivery: {AshOban.Signals, chunks: []}",
                 ", extensions: [AshOban]"
               ) == ""
      end
    end
  end
end
