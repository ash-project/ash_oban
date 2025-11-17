# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Transformers.SetDefaults do
  # Set trigger default values
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(_), do: false

  def before?(AshOban.Transformers.DefineSchedulers), do: true
  def before?(_), do: false

  # sobelow_skip ["DOS.BinToAtom"]
  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    {:ok,
     dsl
     |> set_domain(module)
     |> set_trigger_defaults(module)
     |> set_scheduled_action_defaults(module)
     |> validate_global_uniqueness(module)}
  end

  defp set_domain(dsl, module) do
    case AshOban.Info.oban_domain(dsl) do
      {:ok, domain} when not is_nil(domain) ->
        dsl

      :error ->
        if domain = Ash.Resource.Info.domain(dsl) do
          Transformer.set_option(dsl, [:oban], :domain, domain)
        else
          raise Spark.Error.DslError,
            module: module,
            message:
              "Resources without a statically configured domain require the `domain` option in the `oban` section."
        end
    end
  end

  defp validate_global_uniqueness(dsl, module) do
    triggers = AshOban.Info.oban_triggers(dsl)
    schedulers = AshOban.Info.oban_scheduled_actions(dsl)

    triggers
    |> Enum.concat(schedulers)
    |> Enum.map(& &1.name)
    |> Enum.frequencies()
    |> Enum.find(fn {_, value} ->
      value > 1
    end)
    |> case do
      nil ->
        :ok

      {name, _} ->
        raise Spark.Error.DslError,
          path: [:oban, :triggers, name],
          module: module,
          message: """
          The trigger and/or scheduled_action #{inspect(name)} is defined more than once.
          Names must be unique across scheduled_actions and triggers.
          """
    end

    dsl
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

        _ ->
          :ok
      end

      queue = scheduled_action.queue || default_queue_name(dsl, scheduled_action)

      Transformer.replace_entity(dsl, [:oban, :scheduled_actions], %{
        scheduled_action
        | action: action_name,
          queue: queue,
          shared_context?:
            scheduled_action.shared_context? || AshOban.Info.oban_shared_context?(dsl) || false
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
          action: trigger.action || trigger.name,
          shared_context?:
            trigger.shared_context? || AshOban.Info.oban_shared_context?(dsl) || false,
          use_tenant_from_record?:
            trigger.use_tenant_from_record? || AshOban.Info.oban_use_tenant_from_record?(dsl) ||
              false
      })
    end)
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp default_queue_name(dsl, trigger) do
    :"#{Ash.Resource.Info.short_name(dsl)}_#{trigger.name}"
  end
end
