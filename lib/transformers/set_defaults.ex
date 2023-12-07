defmodule AshOban.Transformers.SetDefaults do
  # Set trigger default values
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(AshOban.Transformers.DefineSchedulers), do: false
  def after?(_), do: true
  def before?(AshOban.Transformers.DefineSchedulers), do: true
  def before?(_), do: false

  # sobelow_skip ["DOS.BinToAtom"]
  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    {:ok,
     dsl
     |> set_trigger_defaults(module)
     |> set_scheduled_action_defaults(module)}
  end

  defp set_scheduled_action_defaults(dsl, module) do
    dsl
    |> Transformer.get_entities([:oban, :scheduled_actions])
    |> Enum.reduce(dsl, fn scheduled_action, dsl ->
      action_name = scheduled_action.action || scheduled_action.name

      case Ash.Resource.Info.action(dsl, action_name) do
        nil ->
          key_name =
            if scheduled_action.action do
              :action
            else
              :name
            end

          raise Spark.Error.DslError,
            path: [:oban, :scheduled_actions, scheduled_action.name, key_name],
            module: module,
            message: """
            No such action #{inspect(action_name)} on #{inspect(module)}.
            """

        %{type: bad_type} when bad_type in [:update, :destroy] ->
          raise Spark.Error.DslError,
            path: [:oban, :scheduled_actions, scheduled_action.name],
            module: module,
            message: """
            Scheduled actions of type #{inspect(bad_type)} are not supported.
            """
      end

      queue = scheduled_action.queue || default_queue_name(dsl, scheduled_action)

      Transformer.replace_entity(dsl, [:oban, :scheduled_actions], %{
        scheduled_action
        | action: action_name,
          queue: queue
      })
    end)
  end

  defp set_trigger_defaults(dsl, module) do
    dsl
    |> Transformer.get_entities([:oban, :triggers])
    |> Enum.reduce(dsl, fn trigger, dsl ->
      read_action =
        case trigger.read_action do
          nil ->
            Ash.Resource.Info.primary_action(dsl, :read) ||
              raise Spark.Error.DslError,
                path: [
                  :oban,
                  :triggers,
                  trigger.name,
                  :read_action
                ],
                module: module,
                message: """
                No read action was configured for this trigger, and no primary read action exists
                """

          read_action ->
            Ash.Resource.Info.action(dsl, read_action)
        end

      action_name = trigger.action || trigger.name

      unless Ash.Resource.Info.action(dsl, action_name) do
        key_name =
          if trigger.action do
            :action
          else
            :name
          end

        raise Spark.Error.DslError,
          path: [:oban, :triggers, trigger.name, key_name],
          module: module,
          message: """
          No such action #{inspect(action_name)} on #{inspect(module)}.
          """
      end

      unless read_action.pagination && read_action.pagination.keyset? do
        raise Spark.Error.DslError,
          path: [:oban, :triggers, trigger.name, :read_action],
          module: module,
          message: """
          The read action `:#{read_action.name}` must support keyset pagination in order to be
          used by an AshOban trigger.
          """
      end

      queue = trigger.queue || default_queue_name(dsl, trigger)

      Transformer.replace_entity(dsl, [:oban, :triggers], %{
        trigger
        | read_action: read_action.name,
          queue: queue,
          scheduler_queue: trigger.scheduler_queue || queue,
          action: trigger.action || trigger.name
      })
    end)
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp default_queue_name(dsl, trigger) do
    :"#{Ash.Resource.Info.short_name(dsl)}_#{trigger.name}"
  end
end
