defmodule AshOban.Transformers.DefineSchedulers do
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(AshOban.Transformers.SetDefaults), do: true
  def after?(_), do: false

  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    dsl
    |> AshOban.Info.oban_triggers()
    |> Enum.reduce(dsl, fn trigger, dsl ->
      scheduler_module_name = module_name(module, trigger, "Scheduler")
      worker_module_name = module_name(module, trigger, "Worker")

      dsl
      |> Transformer.replace_entity([:oban, :triggers], %{
        trigger
        | scheduler: scheduler_module_name,
          worker: worker_module_name
      })
      |> Transformer.async_compile(fn ->
        define_worker(module, worker_module_name, trigger, dsl)
      end)
      |> Transformer.async_compile(fn ->
        define_scheduler(module, scheduler_module_name, worker_module_name, trigger, dsl)
      end)
    end)
    |> then(&{:ok, &1})
  end

  defp module_name(module, trigger, type) do
    module
    |> List.wrap()
    |> Enum.concat(["AshOban", type])
    |> Enum.concat([Macro.camelize(to_string(trigger.name))])
    |> Module.concat()
  end

  defp define_scheduler(resource, scheduler_module_name, worker_module_name, trigger, dsl) do
    api = AshOban.Info.oban_api!(dsl)
    primary_key = Ash.Resource.Info.primary_key(dsl)
    pro? = AshOban.Info.pro?()

    filter =
      if not is_nil(trigger.where) do
        quote do
          def filter(query) do
            Ash.Query.do_filter(query, unquote(Macro.escape(trigger.where)))
          end
        end
      end

    stream =
      if is_nil(trigger.where) do
        quote do
          def stream(resource) do
            resource
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.select(unquote(primary_key))
            |> Ash.Query.for_read(unquote(trigger.read_action))
            |> unquote(api).stream!()
          end
        end
      else
        quote do
          def stream(resource) do
            resource
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.select(unquote(primary_key))
            |> Ash.Query.for_read(unquote(trigger.read_action))
            |> filter()
            |> unquote(api).stream!()
          end
        end
      end

    insert =
      if pro? do
        quote do
          def insert(stream) do
            stream
            |> Stream.chunk_every(100)
            |> Stream.each(&Oban.insert_all!/1)
            |> Stream.run()
          end
        end
      else
        quote do
          def insert(stream) do
            stream
            |> Stream.each(&Oban.insert!())
            |> Stream.run()
          end
        end
      end

    worker =
      if pro? do
        Oban.Pro.Worker
      else
        Oban.Worker
      end

    function_name =
      if pro? do
        :process
      else
        :perform
      end

    quoted =
      quote do
        use unquote(worker),
          queue: unquote(trigger.scheduler_queue),
          unique: [
            period: :infinity,
            states: [
              :available,
              :retryable,
              :scheduled
            ]
          ],
          max_attempts: unquote(trigger.max_scheduler_attempts)

        require Logger

        @impl unquote(worker)
        if unquote(trigger.state != :active) do
          def unquote(function_name)(%Oban.Job{}) do
            {:discard, unquote(trigger.state)}
          end
        else
          def unquote(function_name)(%Oban.Job{}) do
            unquote(resource)
            |> stream()
            |> Stream.map(fn record ->
              unquote(worker_module_name).new(%{
                primary_key: Map.take(record, unquote(primary_key))
              })
            end)
            |> insert()
          end
        end

        unquote(stream)
        unquote(filter)
        unquote(insert)
      end

    Module.create(scheduler_module_name, quoted, Macro.Env.location(__ENV__))
  end

  defp define_worker(resource, worker_module_name, trigger, dsl) do
    api = AshOban.Info.oban_api!(dsl)
    pro? = AshOban.Info.pro?()

    worker =
      if pro? do
        Oban.Pro.Worker
      else
        Oban.Worker
      end

    function_name =
      if pro? do
        :process
      else
        :perform
      end

    query =
      if is_nil(trigger.where) do
        quote do
          def query do
            unquote(resource)
          end
        end
      else
        quote do
          def query do
            Ash.Query.do_filter(unquote(resource), unquote(Macro.escape(trigger.where)))
          end
        end
      end

    Module.create(
      worker_module_name,
      quote do
        use unquote(worker),
          max_attempts: 3,
          queue: unquote(trigger.queue),
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
        if unquote(trigger.state != :active) do
          def unquote(function_name)(_) do
            {:discard, unquote(trigger.state)}
          end
        else
          def unquote(function_name)(%Oban.Job{args: %{"primary_key" => primary_key}}) do
            if Ash.DataLayer.data_layer_can?(unquote(resource), :transact) do
              Ash.DataLayer.transaction(
                unquote(resource),
                fn ->
                  opts = [
                    action: unquote(trigger.read_action),
                    context: %{private: %{ash_oban?: true}}
                  ]

                  opts =
                    if Ash.DataLayer.data_layer_can?(unquote(resource), {:lock, :for_update}) do
                      opts
                    else
                      Keyword.put(opts, :lock, :for_update)
                    end

                  query()
                  |> unquote(api).read_one(primary_key, opts)
                  |> case do
                    {:ok, nil} ->
                      {:discard, :trigger_no_longer_applies}

                    {:ok, record} ->
                      nil
                  end
                  |> Ash.Changeset.new()
                  |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                  |> Ash.Changeset.for_update(unquote(trigger.action), %{})
                  |> unquote(api).update!()
                end,
                nil,
                %{
                  type: :ash_oban_trigger,
                  metadata: %{
                    resource: unquote(resource),
                    trigger: unquote(trigger.name)
                  }
                }
              )
              |> case do
                {:ok, {:discard, reason}} ->
                  {:discard, reason}

                {:ok, _} ->
                  :ok

                other ->
                  other
              end
            else
              opts = [
                action: unquote(trigger.read_action),
                context: %{private: %{ash_oban?: true}}
              ]

              query()
              |> unquote(api).read_one(primary_key, opts)
              |> case do
                {:ok, nil} ->
                  {:discard, :trigger_no_longer_applies}

                {:ok, record} ->
                  nil
              end
              |> Ash.Changeset.new()
              |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
              |> Ash.Changeset.for_update(unquote(trigger.action), %{})
              |> unquote(api).update()
            end
          end
        end

        unquote(query)
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
