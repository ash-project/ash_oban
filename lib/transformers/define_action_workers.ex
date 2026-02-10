# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Transformers.DefineActionWorkers do
  # Define scheduler and worker modules.
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(_), do: true

  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    dsl
    |> AshOban.Info.oban_scheduled_actions()
    |> Enum.reduce(dsl, fn scheduled_action, dsl ->
      worker_module_name =
        scheduled_action.worker_module_name || module_name(module, scheduled_action)

      define_worker(module, worker_module_name, scheduled_action, dsl)

      dsl
      |> Transformer.replace_entity([:oban, :scheduled_actions], %{
        scheduled_action
        | worker: worker_module_name
      })
    end)
    |> then(&{:ok, &1})
  end

  defp module_name(module, trigger) do
    module
    |> List.wrap()
    |> Enum.concat(["AshOban", "ActionWorker"])
    |> Enum.concat([Macro.camelize(to_string(trigger.name))])
    |> Module.concat()
  end

  # sobelow_skip ["SQL.Query"]
  defp define_worker(resource, worker_module_name, scheduled_action, dsl) do
    domain = AshOban.Info.oban_domain!(dsl)
    pro? = AshOban.Info.pro?()

    function_name =
      if pro? do
        :process
      else
        :perform
      end

    worker =
      if pro? do
        Oban.Pro.Worker
      else
        Oban.Worker
      end

    Module.create(
      worker_module_name,
      quote location: :keep do
        use unquote(worker),
          priority: unquote(scheduled_action.priority),
          max_attempts: unquote(scheduled_action.max_attempts),
          queue: unquote(scheduled_action.queue),
          unique: [
            period: :infinity,
            states: :incomplete
          ]

        require Logger
        @impl unquote(worker)
        def unquote(function_name)(%Oban.Job{args: args} = job) do
          scheduled_action =
            AshOban.Info.oban_scheduled_action(unquote(resource), unquote(scheduled_action.name))

          (scheduled_action.list_tenants ||
             AshOban.Info.oban_list_tenants!(unquote(resource)))
          |> then(fn
            {module, o} ->
              module.list_tenants(o)

            list_tenants ->
              list_tenants
          end)
          |> Enum.each(fn tenant ->
            case AshOban.lookup_actor(args["actor"], unquote(scheduled_action.actor_persister)) do
              {:ok, actor} ->
                authorize? = AshOban.authorize?()

                AshOban.debug(
                  "Scheduled action #{unquote(inspect(resource))}.#{unquote(scheduled_action.name)} triggered.",
                  unquote(scheduled_action.debug?)
                )

                input =
                  (args["action_arguments"] || %{})
                  |> Map.merge(unquote(Macro.escape(scheduled_action.action_input || %{})))

                input =
                  if job.max_attempts == job.attempt do
                    Map.put(input, :last_oban_attempt?, true)
                  else
                    Map.put(input, :last_oban_attempt?, false)
                  end

                unquote(resource)
                |> Ash.ActionInput.new()
                |> Ash.ActionInput.set_tenant(tenant)
                |> Ash.ActionInput.set_context(
                  if unquote(scheduled_action.shared_context?) do
                    %{shared: %{private: %{ash_oban?: true}}}
                  else
                    %{private: %{ash_oban?: true}}
                  end
                )
                |> Ash.ActionInput.for_action(
                  unquote(scheduled_action.action),
                  input,
                  authorize?: authorize?,
                  actor: actor,
                  domain: unquote(domain),
                  skip_unknown_inputs: Map.keys(input)
                )
                |> Ash.run_action!()

              {:error, error} ->
                raise Ash.Error.to_ash_error(error)
            end
          end)

          :ok
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
