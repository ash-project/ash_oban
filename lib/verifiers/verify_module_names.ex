# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Verifiers.VerifyModuleNames do
  @moduledoc "Verifies that module names have been set for triggers and scheduled actions"
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> AshOban.Info.oban_triggers()
    |> Enum.filter(fn trigger ->
      trigger.scheduler_cron && !trigger.scheduler_module_name
    end)
    |> case do
      [] ->
        :ok

      missing ->
        IO.warn("""
        The following triggers do not have a configured scheduler_module_name.
        Each trigger must have a defined module name, otherwise changing
        the name of the trigger will lead to "dangling" jobs. See the
        `AshOban` documentation for more.

        Run `mix ash_oban.set_default_module_names` to fix this automatically.

        #{names_list(module, missing)}
        """)
    end

    dsl_state
    |> AshOban.Info.oban_triggers()
    |> Enum.reject(fn trigger ->
      trigger.worker_module_name
    end)
    |> case do
      [] ->
        :ok

      missing ->
        IO.warn("""
        The following triggers do not have a configured worker_module_name.
        Each trigger must have a defined module name, otherwise changing
        the name of the trigger will lead to "dangling" jobs. See the
        `AshOban` documentation for more.

        Run `mix ash_oban.set_default_module_names` to fix this automatically.

        #{names_list(module, missing)}
        """)
    end

    dsl_state
    |> AshOban.Info.oban_scheduled_actions()
    |> Enum.reject(fn trigger ->
      trigger.worker_module_name
    end)
    |> case do
      [] ->
        :ok

      missing ->
        IO.warn("""
        The following scheduled actions do not have a configured module_name.
        Each scheduled action must have a defined module name, otherwise changing
        the name of the trigger will lead to "dangling" jobs. See the
        `AshOban` documentation for more.

        Run `mix ash_oban.set_default_module_names` to fix this automatically.

        #{names_list(module, missing)}
        """)
    end
  end

  defp names_list(module, triggers) do
    Enum.map_join(triggers, "\n", &"- #{inspect(module)}.#{&1.name}")
  end
end
