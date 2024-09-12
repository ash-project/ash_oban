defmodule AshOban.Transformers.DefineSchedulers do
  # Define scheduler and worker modules.
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(_), do: true

  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    dsl
    |> AshOban.Info.oban_triggers()
    |> Enum.reduce(dsl, fn trigger, dsl ->
      scheduler_module_name =
        if trigger.scheduler_cron do
          module_name(module, trigger, "Scheduler")
        end

      worker_module_name = module_name(module, trigger, "Worker")

      define_worker(module, worker_module_name, trigger, dsl)

      dsl
      |> Transformer.replace_entity([:oban, :triggers], %{
        trigger
        | scheduler: scheduler_module_name,
          worker: worker_module_name
      })
      |> then(fn dsl ->
        if trigger.scheduler_cron do
          Transformer.async_compile(dsl, fn ->
            define_scheduler(module, scheduler_module_name, worker_module_name, trigger, dsl)
          end)
        else
          dsl
        end
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
    domain = AshOban.Info.oban_domain!(dsl)
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

    limit_stream =
      if trigger.record_limit do
        quote do
          def limit_stream(query) do
            Ash.Query.limit(query, unquote(trigger.record_limit))
          end
        end
      else
        quote do
          def limit_stream(query) do
            query
          end
        end
      end

    batch_opts =
      if trigger.stream_batch_size do
        quote do
          [batch_size: unquote(trigger.stream_batch_size)]
        end
      else
        quote do
          []
        end
      end

    stream =
      if is_nil(trigger.where) do
        quote location: :keep do
          def stream(resource, actor) do
            resource
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.select(unquote(primary_key))
            |> limit_stream()
            |> Ash.Query.for_read(unquote(trigger.read_action), %{},
              authorize?: AshOban.authorize?(),
              actor: actor,
              domain: unquote(domain)
            )
            |> Ash.stream!(unquote(batch_opts))
          end
        end
      else
        quote location: :keep do
          def stream(resource, actor) do
            resource
            |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
            |> Ash.Query.select(unquote(primary_key))
            |> limit_stream()
            |> filter()
            |> Ash.Query.for_read(unquote(trigger.read_action), %{},
              authorize?: AshOban.authorize?(),
              actor: actor,
              domain: unquote(domain)
            )
            |> Ash.stream!()
          end
        end
      end

    insert =
      if pro? do
        quote location: :keep do
          defp insert(stream) do
            count =
              stream
              |> Stream.chunk_every(100)
              |> Stream.map(fn batch ->
                Oban.insert_all(batch)
                Enum.count(batch)
              end)
              |> Enum.sum()

            AshOban.debug(
              "Scheduled #{count} jobs for trigger #{unquote(inspect(resource))}.#{unquote(trigger.name)}",
              unquote(trigger.debug?)
            )

            :ok
          end
        end
      else
        quote location: :keep do
          defp insert(stream) do
            count =
              stream
              |> Stream.each(&Oban.insert!/1)
              |> Enum.count()

            AshOban.debug(
              "Scheduled #{count} jobs for trigger #{unquote(inspect(resource))}.#{unquote(trigger.name)}",
              unquote(trigger.debug?)
            )

            :ok
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
          priority: unquote(trigger.worker_priority),
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
          def unquote(function_name)(%Oban.Job{args: args}) do
            metadata =
              case AshOban.Info.oban_trigger(unquote(resource), unquote(trigger.name)) do
                %{read_metadata: read_metadata} when is_function(read_metadata) ->
                  read_metadata

                _ ->
                  fn _ -> %{} end
              end

            case AshOban.lookup_actor(args["actor"]) do
              {:ok, actor} ->
                unquote(resource)
                |> stream(actor)
                |> Stream.map(fn record ->
                  unquote(worker_module_name).new(%{
                    primary_key: Map.take(record, unquote(primary_key)),
                    metadata: metadata.(record),
                    actor: args["actor"]
                  })
                end)
                |> insert()

              {:error, e} ->
                raise Ash.Error.to_ash_error(e)
            end
          rescue
            e ->
              Logger.error(
                "Error running AshOban scheduler #{__MODULE__}.\n#{Exception.format(:error, e, __STACKTRACE__)}"
              )

              reraise e, __STACKTRACE__
          end
        end

        unquote(limit_stream)
        unquote(stream)
        unquote(filter)
        unquote(insert)
      end

    Module.create(scheduler_module_name, quoted, Macro.Env.location(__ENV__))
  end

  # sobelow_skip ["SQL.Query"]
  defp define_worker(resource, worker_module_name, trigger, dsl) do
    domain = AshOban.Info.oban_domain!(dsl)
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

    trigger_action = Ash.Resource.Info.action(dsl, trigger.action)

    work_transaction? =
      can_transact? && trigger_action.transaction?

    atomic? = Map.get(trigger_action, :require_atomic?, false)

    can_lock? = Ash.DataLayer.data_layer_can?(dsl, {:lock, :for_update})

    read_action =
      trigger.worker_read_action || trigger.read_action ||
        Map.get(trigger_action, :atomic_upgrade_with) ||
        Ash.Resource.Info.primary_action!(resource, :read).name

    get_and_lock =
      if atomic? do
        quote do
          filter = query().filter
          Ash.Changeset.filter(changeset, filter)
        end
      else
        if can_lock? do
          quote do
            Ash.Changeset.before_action(changeset, fn changeset ->
              query()
              |> Ash.Query.do_filter(primary_key)
              |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
              |> Ash.Query.for_read(unquote(read_action), %{},
                authorize?: authorize?,
                actor: actor,
                domain: unquote(domain)
              )
              |> Ash.Query.lock(:for_update)
              |> Ash.read_one()
              |> case do
                {:ok, nil} ->
                  Ash.Changeset.add_error(
                    changeset,
                    AshOban.Errors.TriggerNoLongerApplies.exception([])
                  )

                {:ok, record} ->
                  %{changeset | data: record}

                {:error, error} ->
                  Ash.Changeset.add_error(changeset, error)
              end
            end)
          end
        else
          quote do
            Ash.Changeset.before_action(changeset, fn changeset ->
              query()
              |> Ash.Query.do_filter(primary_key)
              |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
              |> Ash.Query.for_read(unquote(read_action), %{},
                authorize?: authorize?,
                actor: actor,
                domain: unquote(domain)
              )
              |> Ash.read_one()
              |> case do
                {:ok, nil} ->
                  Ash.Changeset.add_error(
                    changeset,
                    AshOban.Errors.TriggerNoLongerApplies.exception([])
                  )

                {:ok, record} ->
                  %{changeset | data: record}

                {:error, error} ->
                  Ash.Changeset.add_error(changeset, error)
              end
            end)
          end
        end
      end

    prepare_error =
      if on_error_transaction? do
        quote location: :keep do
          defp prepare_error(changeset, primary_key, authorize?, actor) do
            unquote(get_and_lock)
          end
        end
      else
        quote location: :keep do
          defp prepare_error(changeset, _, _, _), do: changeset
        end
      end

    prepare =
      if work_transaction? do
        quote location: :keep do
          defp prepare(changeset, primary_key, authorize?, actor) do
            unquote(get_and_lock)
          end
        end
      else
        quote location: :keep do
          defp prepare(changeset, _, _, _), do: changeset
        end
      end

    handle_error = handle_error(trigger, resource, domain, read_action)

    work =
      work(trigger, worker, atomic?, trigger_action.type, pro?, read_action, resource, domain)

    Module.create(
      worker_module_name,
      quote location: :keep do
        use unquote(worker),
          priority: unquote(trigger.scheduler_priority),
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
        unquote(prepare)
        unquote(prepare_error)
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp handle_error(trigger, resource, domain, read_action) do
    log_final_error =
      if trigger.log_errors? || trigger.log_final_error? do
        quote do
          Logger.error("""
          Error occurred for #{inspect(unquote(resource))}: #{inspect(primary_key)}!

          Error occurred on action: #{unquote(trigger.action)}.

          #{inspect(Exception.format(:error, error, AshOban.stacktrace(error)))}
          """)
        end
      else
        quote do
          _ = primary_key
          _ = error
        end
      end

    log_error =
      if trigger.log_errors? do
        quote do
          Logger.error("""
          Error occurred for #{inspect(unquote(resource))}: #{inspect(primary_key)}!

          Error occurred on action: #{unquote(trigger.action)}.

          #{inspect(Exception.format(:error, error, AshOban.stacktrace(error)))}
          """)
        end
      else
        quote do
          _ = primary_key
          _ = error
        end
      end

    if trigger.on_error do
      # We look up the record again since we have exited any potential transaction we were in before
      quote location: :keep do
        def handle_error(
              %{max_attempts: max_attempts, attempt: attempt},
              error,
              primary_key,
              stacktrace
            )
            when max_attempts != attempt do
          unquote(log_error)
          reraise error, stacktrace
        end

        def handle_error(
              %{max_attempts: max_attempts, attempt: max_attempts, args: args} = job,
              error,
              primary_key,
              stacktrace
            ) do
          authorize? = AshOban.authorize?()

          case AshOban.lookup_actor(args["actor"]) do
            {:ok, actor} ->
              query()
              |> Ash.Query.do_filter(primary_key)
              |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
              |> Ash.Query.for_read(unquote(read_action), %{},
                authorize?: authorize?,
                actor: actor,
                domain: unquote(domain)
              )
              |> Ash.read_one()
              |> case do
                {:error, error} ->
                  AshOban.debug(
                    """
                    Record with primary key #{inspect(primary_key)} encountered an error in #{unquote(inspect(resource))}#{unquote(trigger.name)}

                    #{Exception.format(:error, error, AshOban.stacktrace(error))}
                    """,
                    unquote(trigger.debug?)
                  )

                  {:error, error}

                {:ok, nil} ->
                  AshOban.debug(
                    "Record with primary key #{inspect(primary_key)} no longer applies to trigger #{unquote(inspect(resource))}#{unquote(trigger.name)}",
                    unquote(trigger.debug?)
                  )

                  {:discard, :trigger_no_longer_applies}

                {:ok, record} ->
                  unquote(log_final_error)

                  record
                  |> Ash.Changeset.new()
                  |> prepare_error(primary_key, authorize?, actor)
                  |> case do
                    changeset ->
                      changeset
                      |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                      |> Ash.Changeset.for_action(unquote(trigger.on_error), %{error: error},
                        authorize?: authorize?,
                        actor: actor,
                        domain: unquote(domain),
                        skip_unknown_inputs: [:error]
                      )
                      |> AshOban.update_or_destroy()
                      |> case do
                        :ok ->
                          :ok

                        {:ok, result} ->
                          :ok

                        {:error, error} ->
                          error = Ash.Error.to_ash_error(error, stacktrace)

                          Logger.error("""
                          Error handler failed for #{inspect(unquote(resource))}: #{inspect(primary_key)}!

                          #{inspect(Exception.format(:error, error, AshOban.stacktrace(error)))}
                          """)

                          reraise error, stacktrace
                      end
                  end
              end

            {:error, error} ->
              AshOban.debug(
                """
                Record with primary key #{inspect(primary_key)} encountered an error in #{unquote(inspect(resource))}#{unquote(trigger.name)}

                Could not lookup actor with #{inspect(args["actor"])}

                #{Exception.format(:error, error, AshOban.stacktrace(error))}
                """,
                unquote(trigger.debug?)
              )

              {:error, error}
          end
        end
      end
    else
      quote location: :keep do
        def handle_error(_job, error, primary_key, stacktrace) do
          unquote(log_final_error)
          reraise error, stacktrace
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

  defp work(trigger, worker, atomic?, trigger_action_type, pro?, read_action, resource, domain) do
    function_name =
      if pro? do
        :process
      else
        :perform
      end

    if trigger.state != :active do
      quote location: :keep do
        @impl unquote(worker)
        def unquote(function_name)(_) do
          {:discard, unquote(trigger.state)}
        end
      end
    else
      if atomic? do
        quote location: :keep, generated: true do
          @impl unquote(worker)
          def unquote(function_name)(
                %Oban.Job{args: %{"primary_key" => primary_key} = args} = job
              ) do
            AshOban.debug(
              "Trigger #{unquote(inspect(resource))}.#{unquote(trigger.name)} triggered for primary key #{inspect(primary_key)}",
              unquote(trigger.debug?)
            )

            case AshOban.lookup_actor(args["actor"]) do
              {:ok, actor} ->
                authorize? = AshOban.authorize?()

                args =
                  if unquote(is_nil(trigger.read_metadata)) do
                    %{}
                  else
                    %{metadata: args["metadata"]}
                  end

                query =
                  query()
                  |> Ash.Query.do_filter(primary_key)
                  |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
                  |> Ash.Query.for_read(unquote(read_action), %{},
                    authorize?: authorize?,
                    actor: actor,
                    domain: unquote(domain)
                  )

                if unquote(trigger_action_type) == :update do
                  Ash.bulk_update!(
                    query,
                    unquote(trigger.action),
                    Map.merge(unquote(Macro.escape(trigger.action_input || %{})), args),
                    authorize?: authorize?,
                    actor: actor,
                    domain: unquote(domain),
                    context: %{private: %{ash_oban?: true}},
                    skip_unknown_inputs: [:metadata],
                    return_errors?: true,
                    notify?: true,
                    return_records?: true
                  )
                else
                  Ash.bulk_destroy!(
                    query,
                    unquote(trigger.action),
                    Map.merge(unquote(Macro.escape(trigger.action_input || %{})), args),
                    authorize?: authorize?,
                    actor: actor,
                    domain: unquote(domain),
                    context: %{private: %{ash_oban?: true}},
                    skip_unknown_inputs: [:metadata],
                    return_errors?: true,
                    notify?: true
                  )
                end

                :ok

              {:error, error} ->
                AshOban.debug(
                  """
                  Record with primary key #{inspect(primary_key)} encountered an error in #{unquote(inspect(resource))}#{unquote(trigger.name)}

                  Could not lookup actor with #{inspect(args["actor"])}

                  #{Exception.format(:error, error, AshOban.stacktrace(error))}
                  """,
                  unquote(trigger.debug?)
                )

                raise Ash.Error.to_error_class(error)
            end
          rescue
            error ->
              handle_error(
                job,
                Ash.Error.to_ash_error(error, __STACKTRACE__),
                primary_key,
                __STACKTRACE__
              )
          end
        end
      else
        quote location: :keep, generated: true do
          @impl unquote(worker)
          def unquote(function_name)(
                %Oban.Job{args: %{"primary_key" => primary_key} = args} = job
              ) do
            AshOban.debug(
              "Trigger #{unquote(inspect(resource))}.#{unquote(trigger.name)} triggered for primary key #{inspect(primary_key)}",
              unquote(trigger.debug?)
            )

            case AshOban.lookup_actor(args["actor"]) do
              {:ok, actor} ->
                authorize? = AshOban.authorize?()

                query()
                |> Ash.Query.do_filter(primary_key)
                |> Ash.Query.set_context(%{private: %{ash_oban?: true}})
                |> Ash.Query.for_read(unquote(read_action), %{},
                  authorize?: authorize?,
                  actor: actor,
                  domain: unquote(domain)
                )
                |> Ash.read_one()
                |> case do
                  {:ok, nil} ->
                    AshOban.debug(
                      "Record with primary key #{inspect(primary_key)} no longer applies to trigger #{unquote(inspect(resource))}#{unquote(trigger.name)}",
                      unquote(trigger.debug?)
                    )

                    {:discard, :trigger_no_longer_applies}

                  {:ok, record} ->
                    args =
                      if unquote(is_nil(trigger.read_metadata)) do
                        %{}
                      else
                        %{metadata: args["metadata"]}
                      end

                    record
                    |> Ash.Changeset.new()
                    |> prepare(primary_key, authorize?, actor)
                    |> Ash.Changeset.set_context(%{private: %{ash_oban?: true}})
                    |> Ash.Changeset.for_action(
                      unquote(trigger.action),
                      Map.merge(unquote(Macro.escape(trigger.action_input || %{})), args),
                      authorize?: authorize?,
                      actor: actor,
                      domain: unquote(domain),
                      skip_unknown_input: [:metadata]
                    )
                    |> AshOban.update_or_destroy()
                    |> case do
                      :ok ->
                        :ok

                      {:ok, result} ->
                        {:ok, result}

                      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} ->
                        AshOban.debug(
                          "Record with primary key #{inspect(primary_key)} no longer applies to trigger #{unquote(inspect(resource))}#{unquote(trigger.name)}",
                          unquote(trigger.debug?)
                        )

                        {:discard, :trigger_no_longer_applies}

                      {:error,
                       %Ash.Error.Invalid{errors: [%AshOban.Errors.TriggerNoLongerApplies{}]}} ->
                        AshOban.debug(
                          "Record with primary key #{inspect(primary_key)} no longer applies to trigger #{unquote(inspect(resource))}#{unquote(trigger.name)}",
                          unquote(trigger.debug?)
                        )

                        {:discard, :trigger_no_longer_applies}

                      {:error, error} ->
                        raise Ash.Error.to_error_class(error)
                    end
                end

              {:error, error} ->
                AshOban.debug(
                  """
                  Record with primary key #{inspect(primary_key)} encountered an error in #{unquote(inspect(resource))}#{unquote(trigger.name)}

                  Could not lookup actor with #{inspect(args["actor"])}

                  #{Exception.format(:error, error, AshOban.stacktrace(error))}
                  """,
                  unquote(trigger.debug?)
                )

                raise Ash.Error.to_error_class(error)
            end
          rescue
            error ->
              handle_error(
                job,
                Ash.Error.to_ash_error(error, __STACKTRACE__),
                primary_key,
                __STACKTRACE__
              )
          end
        end
      end
    end
  end
end
