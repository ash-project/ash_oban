defmodule AshOban.Verifiers.DefineSchedulers do
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    # TODO
    # dsl_state
    # |> AshOban.Info.oban_triggers()
    # |> Enum.each(fn trigger ->
    #   IO.inspect(trigger)
    # end)

    :ok
  end
end
