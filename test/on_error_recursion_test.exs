# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.OnErrorRecursionTest.Resource do
  @moduledoc false
  use Ash.Resource,
    domain: AshOban.OnErrorRecursionTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshOban]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :processed, :boolean, default: false, allow_nil?: false
  end

  actions do
    default_accept []
    defaults [:read, :create]

    update :process do
      require_atomic? true
      change set_attribute(:processed, true)
    end

    update :always_fails do
      require_atomic? false
      accept []
      argument :required_thing, :string, allow_nil?: false
    end
  end

  oban do
    domain AshOban.OnErrorRecursionTest.Domain

    triggers do
      trigger :loop do
        action :process
        on_error :always_fails
        where expr(processed != true)
        scheduler_cron false
        worker_read_action :read
        worker_module_name AshOban.OnErrorRecursionTest.Worker
        scheduler_module_name AshOban.OnErrorRecursionTest.Scheduler
      end
    end
  end
end

defmodule AshOban.OnErrorRecursionTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshOban.OnErrorRecursionTest.Resource
  end
end

defmodule AshOban.OnErrorRecursionTest do
  use ExUnit.Case, async: false

  alias AshOban.OnErrorRecursionTest.{Resource, Worker}

  test "a deterministically failing on_error action terminates instead of recursing forever" do
    record =
      Resource
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    job = %Oban.Job{
      id: 1,
      attempt: 2,
      max_attempts: 2,
      args: %{"primary_key" => %{"id" => record.id}},
      worker: to_string(Worker),
      queue: "default",
      state: "executing"
    }

    task =
      Task.async(fn ->
        try do
          Worker.handle_error(job, %RuntimeError{message: "original"}, %{"id" => record.id}, [])
        rescue
          e -> {:raised, e}
        end
      end)

    assert {:raised, _} = Task.await(task, 5_000)
  end
end
