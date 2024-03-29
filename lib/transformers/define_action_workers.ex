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
        module_name(module, scheduled_action)

      dsl
      |> Transformer.async_compile(fn ->
        define_worker(module, worker_module_name, scheduled_action, dsl)
      end)
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
            states: [
              :available,
              :retryable,
              :scheduled
            ]
          ]

        require Logger
        @impl unquote(worker)
        def unquote(function_name)(%Oban.Job{args: args} = job) do
          case AshOban.lookup_actor(args["actor"]) do
            {:ok, actor} ->
              authorize? = AshOban.authorize?()

              AshOban.debug(
                "Scheduled action #{unquote(inspect(resource))}.#{unquote(scheduled_action.name)} triggered.",
                unquote(scheduled_action.debug?)
              )

              input = unquote(Macro.escape(scheduled_action.action_input || %{}))

              input =
                if job.max_attempts == job.attempt do
                  Map.put(input, :last_oban_attempt?, true)
                else
                  Map.put(input, :last_oban_attempt?, false)
                end

              unquote(resource)
              |> Ash.ActionInput.for_action(
                unquote(scheduled_action.action),
                input,
                authorize?: authorize?,
                actor: actor,
                domain: unquote(domain)
              )
              |> Ash.run_action!()

              :ok

            {:error, error} ->
              raise Ash.Error.to_ash_error(error)
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
