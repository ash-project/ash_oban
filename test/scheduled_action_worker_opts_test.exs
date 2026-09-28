# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ScheduledActionWorkerOptsTest do
  use ExUnit.Case, async: true

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshOban.ScheduledActionWorkerOptsTest.Resource
    end
  end

  defmodule Resource do
    use Ash.Resource,
      domain: AshOban.ScheduledActionWorkerOptsTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      scheduled_actions do
        schedule :default_unique, "0 0 1 1 *" do
          action :say_hello
          queue :scheduled_action_worker_opts_default
          worker_module_name AshOban.ScheduledActionWorkerOptsTest.ActionWorker.DefaultUnique
        end

        schedule :custom_unique, "0 0 1 1 *" do
          action :say_hello
          queue :scheduled_action_worker_opts_custom
          tags(["schedule-tag"])

          worker_opts unique: [period: 60, states: :successful], tags: ["extra-tag"]

          worker_module_name AshOban.ScheduledActionWorkerOptsTest.ActionWorker.CustomUnique
        end
      end
    end

    actions do
      defaults create: []

      read :read do
        primary? true
        pagination keyset?: true
      end

      action :say_hello, :string do
        run fn _, _ -> {:ok, "hello"} end
      end
    end

    attributes do
      uuid_primary_key :id
    end
  end

  test "scheduled action workers keep the generated unique options by default" do
    opts = AshOban.ScheduledActionWorkerOptsTest.ActionWorker.DefaultUnique.__opts__()

    assert opts[:unique] == [
             keys: [:primary_key, :action_arguments, :tenant],
             period: :infinity,
             states: :incomplete
           ]

    assert opts[:queue] == :scheduled_action_worker_opts_default
    assert opts[:tags] == []
  end

  test "worker_opts on a scheduled action override the generated worker options" do
    opts = AshOban.ScheduledActionWorkerOptsTest.ActionWorker.CustomUnique.__opts__()

    assert opts[:unique] == [period: 60, states: :successful]
    assert opts[:queue] == :scheduled_action_worker_opts_custom
  end

  test "tags on a scheduled action are merged with tags in worker_opts" do
    opts = AshOban.ScheduledActionWorkerOptsTest.ActionWorker.CustomUnique.__opts__()

    assert Enum.sort(opts[:tags]) == ["extra-tag", "schedule-tag"]
  end
end
