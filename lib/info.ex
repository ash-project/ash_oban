defmodule AshOban.Info do
  use Spark.InfoGenerator, extension: AshOban, sections: [:oban]
  @pro Application.compile_env(:ash_oban, :pro?) || false

  def pro?, do: @pro

  @spec oban_trigger(Ash.Resource.t() | Spark.Dsl.t(), atom) :: nil | AshOban.Trigger.t()
  def oban_trigger(resource, name) do
    resource
    |> oban_triggers()
    |> Enum.find(&(&1.name == name))
  end
end
