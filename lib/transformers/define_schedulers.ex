defmodule AshOban.Transformers.DefineSchedulers do
  @moduledoc """
  Define scheduler and worker modules.
  """

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
        quote location: :keep do
          def filter(query) do
            Ash.Query.do_filter(query, unquote(Macro.escape(trigger.where)))
          end
        end
      end

    stream =
      if is_nil(trigger.where) do
        quote location: :keep do
          def stream(resource) do
            resource
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.select(unquote(primary_key))
            |> Ash.Query.for_read(unquote(trigger.read_action))
            |> unquote(api).stream!()
          end
        end
      else
        quote location: :keep do
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
        quote location: :keep do
          def insert(stream) do
            stream
            |> Stream.chunk_every(100)
            |> Stream.each(&Oban.insert_all/1)
            |> Stream.run()
          end
        end
      else
        quote location: :keep do
          def insert(stream) do
            stream
            |> Stream.each(&Oban.insert!/1)
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
      quote location: :keep do
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

  # sobelow_skip ["SQL.Query"]
  defp define_worker(resource, worker_module_name, trigger, dsl) do
    api = AshOban.Info.oban_api!(dsl)
    pro? = AshOban.Info.pro?()

    worker =
      if pro? do
        Oban.Pro.Worker
      else
        Oban.Worker
      end

    query = query(trigger, resource)

    can_transact? = Ash.DataLayer.data_layer_can?(dsl, :transact)

    on_error_transaction? =
      can_transact? && trigger.on_error &&
        Ash.Resource.Info.action(dsl, trigger.on_error).transaction?

    work_transaction? =
      can_transact? && Ash.Resource.Info.action(dsl, trigger.action).transaction?

    can_lock? = Ash.DataLayer.data_layer_can?(dsl, {:lock, :for_update})

    lock =
      if work_transaction? || on_error_transaction? do
        if can_lock? do
          quote location: :keep do
            defp lock(query) do
              Ash.Query.lock(query, :for_update)
            end
          end
        else
          quote location: :keep do
            defp lock(query), do: query
          end
        end
      end

    handle_error = handle_error(trigger, on_error_transaction?, resource, api)

    work = work(trigger, worker, pro?, resource, api, work_transaction?)

    Module.create(
      worker_module_name,
      quote location: :keep do
        use unquote(worker),
          max_attempts: unquote(trigger.max_attempts),
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

        unquote(work)
        unquote(query)
        unquote(handle_error)
        unquote(lock)
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp handle_error(trigger, on_error_transaction?, resource, api) do
    if trigger.on_error do
      # We look up the record again since we have exited any potential transaction we were in before
      if on_error_transaction? do
        quote location: :keep do
          def handle_error(error, primary_key) do
            Ash.DataLayer.transaction(
              unquote(resource),
              fn ->
                query()
                |> Ash.Query.do_filter(primary_key)
                |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
                |> lock()
                |> Ash.Query.for_read(unquote(trigger.read_action), authorize?: false)
                |> unquote(api).read_one()
                |> case do
                  {:ok, nil} ->
                    {:discard, :trigger_no_longer_applies}

                  {:ok, record} ->
                    record
                    |> Ash.Changeset.new()
                    |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                    |> Ash.Changeset.for_update(unquote(trigger.on_error), %{error: error})
                    |> unquote(api).update(return_notifications?: true)
                    |> case do
                      {:ok, result, notifications} ->
                        notifications

                      {:error, error} ->
                        Ash.DataLayer.rollback(unquote(resource), error)
                    end
                end
              end,
              nil,
              %{
                type: :ash_oban_trigger_error,
                metadata: %{
                  resource: unquote(resource),
                  trigger: unquote(trigger.name),
                  primary_key: primary_key,
                  error: error
                }
              }
            )
            |> case do
              {:ok, {:discard, reason}} ->
                {:discard, reason}

              {:ok, notifications} ->
                Ash.Notifier.notify(notifications)
                :ok

              {:error, error} ->
                Logger.error("""
                Error handler failed for #{inspect(unquote(resource))}: #{inspect(primary_key)}!

                #{inspect(Exception.message(error))}
                """)

                {:error, error}
            end
          end
        end
      else
        quote location: :keep do
          def handle_error(error, primary_key) do
            query()
            |> Ash.Query.do_filter(primary_key)
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.for_read(unquote(trigger.read_action), authorize?: false)
            |> unquote(api).read_one()
            |> case do
              {:ok, nil} ->
                {:discard, :trigger_no_longer_applies}

              {:ok, record} ->
                record
                |> Ash.Changeset.new()
                |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                |> Ash.Changeset.for_update(unquote(trigger.on_error), %{error: error})
                |> unquote(api).update()
                |> case do
                  {:ok, _result} ->
                    :ok

                  {:error, error} ->
                    Logger.error("""
                    Error handler failed for #{inspect(unquote(resource))}: #{inspect(primary_key)}!

                    #{inspect(Exception.message(error))}
                    """)

                    {:error, error}
                end
            end
          end
        end
      end
    else
      quote location: :keep do
        def handle_error(error, _) do
          {:error, error}
        end
      end
    end
  end

  defp query(trigger, resource) do
    if is_nil(trigger.where) do
      quote location: :keep do
        def query do
          unquote(resource)
        end
      end
    else
      quote location: :keep do
        def query do
          Ash.Query.do_filter(unquote(resource), unquote(Macro.escape(trigger.where)))
        end
      end
    end
  end

  defp work(trigger, worker, pro?, resource, api, work_transaction?) do
    function_name =
      if pro? do
        :process
      else
        :perform
      end

    cond do
      trigger.state != :active ->
        quote location: :keep do
          @impl unquote(worker)
          def unquote(function_name)(_) do
            {:discard, unquote(trigger.state)}
          end
        end

      work_transaction? ->
        quote location: :keep do
          @impl unquote(worker)
          def unquote(function_name)(%Oban.Job{args: %{"primary_key" => primary_key}} = job) do
            Ash.DataLayer.transaction(
              unquote(resource),
              fn ->
                query()
                |> Ash.Query.do_filter(primary_key)
                |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
                |> lock()
                |> Ash.Query.for_read(unquote(trigger.read_action), authorize?: false)
                |> unquote(api).read_one()
                |> case do
                  {:ok, nil} ->
                    {:discard, :trigger_no_longer_applies}

                  {:ok, record} ->
                    record
                    |> Ash.Changeset.new()
                    |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                    |> Ash.Changeset.for_update(unquote(trigger.action), %{})
                    |> unquote(api).update(return_notifications?: true)
                    |> case do
                      {:ok, _result, notifications} ->
                        notifications

                      {:error, error} ->
                        Ash.DataLayer.rollback(unquote(resource), error)
                    end
                end
              end,
              nil,
              %{
                type: :ash_oban_trigger,
                metadata: %{
                  resource: unquote(resource),
                  trigger: unquote(trigger.name),
                  primary_key: primary_key
                }
              }
            )
            |> case do
              {:ok, {:discard, reason}} ->
                {:discard, reason}

              {:ok, notifications} ->
                Ash.Notifier.notify(notifications)
                :ok

              {:error, error} ->
                raise Ash.Error.to_error_class(error)
            end
          rescue
            error ->
              handle_error(error, primary_key)
          end
        end

      true ->
        quote location: :keep do
          @impl unquote(worker)
          def unquote(function_name)(%Oban.Job{args: %{"primary_key" => primary_key}} = job) do
            query()
            |> Ash.Query.do_filter(primary_key)
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.for_read(unquote(trigger.read_action), authorize?: false)
            |> unquote(api).read_one()
            |> case do
              {:ok, nil} ->
                {:discard, :trigger_no_longer_applies}

              {:ok, record} ->
                record
                |> Ash.Changeset.new()
                |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                |> Ash.Changeset.for_update(unquote(trigger.action), %{})
                |> unquote(api).update()
                |> case do
                  {:ok, result} ->
                    {:ok, result}

                  {:error, error} ->
                    raise Ash.Error.to_error_class(error)
                end

              # we don't have the record here, so we can't do the `on_error` behavior
              other ->
                other
            end
          rescue
            error ->
              handle_error(error, primary_key)
          end
        end
    end
  end
end
