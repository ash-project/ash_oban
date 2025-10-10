# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Info do
  @moduledoc "Introspection for AshOban"

  use Spark.InfoGenerator, extension: AshOban, sections: [:oban]
  @pro Application.compile_env(:ash_oban, :pro?) || false

  def pro?, do: @pro

  @spec oban_trigger(Ash.Resource.t() | Spark.Dsl.t(), atom) :: nil | AshOban.Trigger.t()
  def oban_trigger(resource, name) do
    resource
    |> oban_triggers()
    |> Enum.find(&(&1.name == name))
  end

  @spec oban_scheduled_action(Ash.Resource.t() | Spark.Dsl.t(), atom) ::
          nil | AshOban.Schedule.t()
  def oban_scheduled_action(resource, name) do
    resource
    |> oban_scheduled_actions()
    |> Enum.find(&(&1.name == name))
  end

  @spec oban_triggers_and_scheduled_actions(Ash.Resource.t() | Spark.Dsl.t()) :: [
          AshOban.Trigger.t()
          | AshOban.Schedule.t()
        ]
  def oban_triggers_and_scheduled_actions(resource) do
    oban_triggers(resource) ++ oban_scheduled_actions(resource)
  end
end
