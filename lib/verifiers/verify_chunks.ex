defmodule AshOban.Verifiers.VerifyChunks do
  @moduledoc "Validates chunk configuration on triggers."
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> AshOban.Info.oban_triggers()
    |> Enum.filter(& &1.chunks)
    |> Enum.reduce_while(:ok, fn trigger, _acc ->
      with :ok <- verify_pro(module, trigger),
           :ok <- verify_action_type(module, trigger, dsl_state),
           :ok <- verify_no_read_metadata(module, trigger) do
        {:cont, :ok}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_pro(module, trigger) do
    if AshOban.Info.pro?() do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:oban, :triggers, trigger.name, :chunks],
         message: """
         Chunks require Oban Pro. Set `config :ash_oban, pro?: true` to use chunk workers.
         """
       )}
    end
  end

  defp verify_action_type(module, trigger, dsl_state) do
    action = Ash.Resource.Info.action(dsl_state, trigger.action)

    if action && action.type == :action do
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:oban, :triggers, trigger.name, :chunks],
         message: """
         Chunks cannot be used with generic actions. Chunks require update or destroy actions
         that operate on records with primary keys.
         """
       )}
    else
      :ok
    end
  end

  defp verify_no_read_metadata(module, trigger) do
    if trigger.read_metadata do
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:oban, :triggers, trigger.name, :chunks],
         message: """
         Chunks cannot be used with `read_metadata`. Per-record metadata is incompatible
         with bulk batch operations.
         """
       )}
    else
      :ok
    end
  end
end
