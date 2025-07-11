defmodule AshOban do
  require Logger

  defmodule Trigger do
    @moduledoc """
    A configured trigger.
    """

    @type t :: %__MODULE__{
            name: atom,
            action: atom,
            read_action: atom,
            queue: atom,
            scheduler_cron: String.t(),
            scheduler_queue: atom,
            lock_for_update?: boolean(),
            action_input: map(),
            max_attempts: pos_integer(),
            worker_module_name: module() | nil,
            scheduler_module_name: module() | nil,
            trigger_once?: boolean(),
            record_limit: pos_integer(),
            extra_args: map() | (map -> map),
            log_final_error?: boolean(),
            log_errors?: boolean(),
            debug?: boolean(),
            actor_persister: module() | :none | nil,
            max_scheduler_attempts: pos_integer(),
            read_metadata: (Ash.Resource.record() -> map),
            stream_batch_size: pos_integer(),
            scheduler_priority: non_neg_integer(),
            worker_priority: non_neg_integer(),
            where: Ash.Expr.t(),
            scheduler: module | nil,
            state: :active | :paused | :deleted,
            worker: module,
            worker_opts: keyword(),
            backoff: pos_integer() | (map -> pos_integer()) | nil,
            timeout: pos_integer() | (map -> pos_integer()) | nil,
            __identifier__: atom,
            on_error: atom,
            on_error_fails_job?: boolean()
          }

    defstruct [
      :name,
      :action,
      :read_action,
      :action_input,
      :extra_args,
      :list_tenants,
      :worker_read_action,
      :lock_for_update?,
      :queue,
      :debug?,
      :worker_module_name,
      :scheduler_module_name,
      :read_metadata,
      :scheduler_cron,
      :scheduler_queue,
      :scheduler_priority,
      :worker_priority,
      :actor_persister,
      :max_attempts,
      :trigger_once?,
      :stream_batch_size,
      :max_scheduler_attempts,
      :record_limit,
      :where,
      :sort,
      :state,
      :scheduler,
      :worker,
      :worker_opts,
      :backoff,
      :timeout,
      :on_error,
      :on_error_fails_job?,
      :log_final_error?,
      :log_errors?,
      :__identifier__
    ]

    def transform(%{read_action: read_action, worker_read_action: nil} = trigger) do
      {:ok, %{trigger | worker_read_action: read_action}}
    end

    def transform(other), do: {:ok, other}
  end

  @trigger %Spark.Dsl.Entity{
    name: :trigger,
    target: Trigger,
    args: [:name],
    identifier: :name,
    imports: [Ash.Expr],
    transform: {Trigger, :transform, []},
    examples: [
      """
      trigger :process do
        action :process
        where expr(processed != true)
        worker_read_action(:read)
      end
      """
    ],
    schema: [
      name: [
        type: :atom,
        doc: "A unique identifier for this trigger."
      ],
      action_input: [
        type: :map,
        doc:
          "Static inputs to supply to the update/destroy action when it is called. Any metadata produced by `read_metadata` will overwrite these values."
      ],
      extra_args: [
        type: {:or, [:map, {:fun, 1}]},
        doc: """
        Additional arguments to merge into the job's arguments map. Can either be a map or a function that takes the record and returns a map.
        """
      ],
      actor_persister: [
        type: {:or, [{:literal, :none}, {:behaviour, AshOban.PersistActor}]},
        doc:
          "An `AshOban.PersistActor` to use to store the actor. Defaults to to the configured `config :ash_oban, :actor_persister`. Set to `:none` to override the configured default."
      ],
      list_tenants: [
        type:
          {:or,
           [
             {:list, :any},
             {:spark_function_behaviour, AshOban.ListTenants, {AshOban.ListTenants.Function, 0}}
           ]},
        doc: """
        A list of tenants or a function behaviour that returns a list of tenants a trigger should be run for.
        """
      ],
      scheduler_queue: [
        type: :atom,
        doc:
          "The queue to place the scheduler job in. The same queue as job is used by default (but with a priority of 1 so schedulers run first)."
      ],
      debug?: [
        type: :boolean,
        default: false,
        doc:
          "If set to `true`, detailed debug logging will be enabled for this trigger. You can also set `config :ash_oban, debug_all_triggers?: true` to enable debug logging for all triggers. If the action has `transaction?: false` this is automatically false."
      ],
      lock_for_update?: [
        type: :boolean,
        default: true,
        doc:
          "If `true`, a transaction will be started before looking up the record, and it will be locked for update. Typically you should leave this on unless you have before/after/around transaction hooks."
      ],
      worker_module_name: [
        type: :module,
        doc: """
        The module name to be used for the generated worker.
        """
      ],
      scheduler_module_name: [
        type: :module,
        doc: """
        The module name to be used for the generated scheduler.
        """
      ],
      scheduler_cron: [
        type: {:or, [:string, {:literal, false}]},
        default: "* * * * *",
        doc: """
        A crontab configuration for when the job should run. Defaults to once per minute (\"* * * * *\"). Use `false` to disable the scheduler entirely.
        """
      ],
      stream_batch_size: [
        type: :pos_integer,
        doc:
          "The batch size to pass when streaming records from using `Ash.stream!/2`. No batch size is passed if none is provided here, so the default is used."
      ],
      queue: [
        type: :atom,
        doc:
          "The queue to place the job in. Defaults to the resources short name plus the name of the trigger."
      ],
      record_limit: [
        type: :pos_integer,
        doc:
          "If set, any given run of the scheduler will only ever schedule this many items maximum."
      ],
      log_errors?: [
        type: :boolean,
        default: true,
        doc: "Whether or not to log errors that occur when performing an action."
      ],
      log_final_error?: [
        type: :boolean,
        default: true,
        doc:
          "If true, logs that an error occurred on the final attempt to perform an action even if `log_errors?` is set to false."
      ],
      worker_priority: [
        type: :non_neg_integer,
        doc: "A number from 0 to 3, where 0 is the highest priority and 3 is the lowest.",
        default: 2
      ],
      scheduler_priority: [
        type: :non_neg_integer,
        doc: "A number from 0 to 3, where 0 is the highest priority and 3 is the lowest.",
        default: 3
      ],
      max_scheduler_attempts: [
        type: :pos_integer,
        default: 1,
        doc: "How many times to attempt scheduling of the triggered action."
      ],
      max_attempts: [
        type: :pos_integer,
        default: 1,
        doc: """
        How many times to attempt the job. After all attempts have been exhausted, the scheduler may just reschedule it. Use the `on_error` action to update the record to make the scheduler no longer apply.
        """
      ],
      trigger_once?: [
        type: :boolean,
        default: false,
        doc: """
        If set to `true` `completed` is added to list of states to check for uniqueness.

        If the execution time of the job is very low, it's possible that jobs are executed and
        completed while the scheduler is running. This can lead to jobs being scheduled for resources
        that are already processed by the time the job gets inserted. Adding `completed` to the list of
        states will lead to oban ignoring the job when inserted.

        Only use this if nothing else is writing to the resource attribute that marks it as processsed.
        Because it will not be processed again as long the completed job is still in the db. You also don't
        need this if the job executing puts the record into a state that makes it no longer eligible for scheduling.
        """
      ],
      read_metadata: [
        type: {:fun, 1},
        doc: """
        Takes a record, and returns metadata to be given to the update action as an argument called `metadata`.
        """
      ],
      state: [
        type: {:one_of, [:active, :paused, :deleted]},
        default: :active,
        doc: """
        Describes the state of the cron job. See the getting started guide for more information. The most important thing is that you *do not remove a trigger from a resource if you are using oban pro*.
        """
      ],
      read_action: [
        type: :atom,
        doc: """
        The read action to use when querying records. Defaults to the primary read. This action *must* support keyset pagination.
        """
      ],
      worker_read_action: [
        type: :atom,
        doc: """
        The read action to use when fetching the individual records for the trigger. Defaults to `read_action`. If you customize this, ensure your action handles scenarios where the trigger is no longer relevant.
        """
      ],
      action: [
        type: :atom,
        required: true,
        doc:
          "The action to be triggered. Defaults to the identifier of the resource plus the name of the trigger"
      ],
      where: [
        type: :any,
        doc: "The filter expression to determine if something should be triggered"
      ],
      sort: [
        type: :any,
        doc: "The sort applied to the query that determines if something should be triggered"
      ],
      on_error: [
        type: :atom,
        doc:
          "An update action to call after the last attempt has failed. See the getting started guide for more."
      ],
      on_error_fails_job?: [
        type: :boolean,
        default: false,
        doc: """
        Determines if the oban job will be failed on the last attempt when there is an on_error handler that is called. If there is no on_error, then the action is always marked as failed on the last attempt.
        """
      ],
      worker_opts: [
        type: :keyword_list,
        default: [],
        doc: """
        Options to set on the worker.

        ATTENTION: this may overwrite options set by ash_oban, make sure you know what you are doing.

        See [Oban.Worker](https://hexdocs.pm/oban/Oban.Worker.html#module-defining-workers) for options
        and [Oban.Pro.Worker](https://oban.pro/docs/pro/Oban.Pro.Worker.html) for oban pro
        """
      ],
      backoff: [
        type: {:or, [:pos_integer, {:fun, 1}]},
        doc: """
        Configure after how much time job should (in seconds) be retried in case of error if more retries available.
        Can be a number of seconds or a function that takes the job and returns a number of seconds.
        Will not be executed if default max_attempts value of 1 will be used.

        See [Oban.Worker](https://hexdocs.pm/oban/Oban.Worker.html#module-customizing-backoff) for more about backoff.
        """
      ],
      timeout: [
        type: {:or, [:pos_integer, {:fun, 1}]},
        doc: """
        Configure timeout for the job in milliseconds.

        See [Oban.Worker timeout](https://hexdocs.pm/oban/Oban.Worker.html#module-customizing-timeout) for more about timeout.
        """
      ]
    ]
  }

  defmodule Schedule do
    @moduledoc """
    A configured scheduled action.
    """

    @type t :: %__MODULE__{
            name: atom,
            action: atom,
            cron: String.t(),
            action_input: map(),
            worker: module(),
            worker_module_name: module() | nil,
            max_attempts: non_neg_integer(),
            queue: atom,
            debug?: boolean,
            actor_persister: module() | :none | nil,
            state: :active | :paused | :deleted,
            priority: non_neg_integer()
          }

    defstruct [
      :name,
      :action,
      :cron,
      :debug,
      :priority,
      :actor_persister,
      :worker_module_name,
      :action_input,
      :max_attempts,
      :queue,
      :worker,
      :debug?,
      :state,
      :__identifier__
    ]
  end

  @schedule %Spark.Dsl.Entity{
    name: :schedule,
    target: Schedule,
    args: [:name, :cron],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        doc: "A unique identifier for this scheduled action."
      ],
      cron: [
        type: :string,
        doc: "The schedule in crontab notation"
      ],
      action_input: [
        type: :map,
        doc: "Inputs to supply to the action when it is called."
      ],
      action: [
        type: :atom,
        doc: "The generic or create action to call when the schedule is triggered."
      ],
      actor_persister: [
        type: {:or, [{:literal, :none}, {:behaviour, AshOban.PersistActor}]},
        doc:
          "An `AshOban.PersistActor` to use to store the actor. Defaults to to the configured `config :ash_oban, :actor_persister`. Set to `:none` to override the configured default."
      ],
      worker_module_name: [
        type: :module,
        doc: """
        The module name to be used for the generated worker.
        """
      ],
      queue: [
        type: :atom,
        doc:
          "The queue to place the job in. Defaults to the resources short name plus the name of the scheduled action (not the action name)."
      ],
      state: [
        type: {:one_of, [:active, :paused, :deleted]},
        default: :active,
        doc: """
        Describes the state of the cron job. See the getting started guide for more information. The most important thing is that you *do not remove a scheduled action from a resource if you are using oban pro*.
        """
      ],
      max_attempts: [
        type: :pos_integer,
        default: 1,
        doc: """
        How many times to attempt the job. The action will receive a `last_oban_attempt?` argument on the last attempt, and you should handle errors accordingly.
        """
      ],
      priority: [
        type: :non_neg_integer,
        doc: "A number from 0 to 3, where 0 is the highest priority and 3 is the lowest.",
        default: 3
      ],
      debug?: [
        type: :boolean,
        default: false,
        doc:
          "If set to `true`, detailed debug logging will be enabled for this trigger. You can also set `config :ash_oban, debug_all_triggers?: true` to enable debug logging for all triggers."
      ]
    ]
  }

  @scheduled_actions %Spark.Dsl.Section{
    name: :scheduled_actions,
    entities: [@schedule],
    describe: """
    A section for configured scheduled actions. Supports generic and create actions.
    """,
    examples: [
      """
      scheduled_actions do
        schedule :import, "0 */6 * * *", action: :import
      end
      """
    ]
  }

  @triggers %Spark.Dsl.Section{
    name: :triggers,
    entities: [@trigger],
    examples: [
      """
      triggers do
        trigger :process do
          action :process
          where expr(processed != true)
          worker_read_action(:read)
        end
      end
      """
    ]
  }

  @oban %Spark.Dsl.Section{
    name: :oban,
    examples: [
      """
      oban do
        triggers do
          trigger :process do
            action :process
            where expr(processed != true)
            worker_read_action(:read)
          end
        end
      end
      """
    ],
    schema: [
      domain: [
        type: {:behaviour, Ash.Domain},
        doc:
          "The Domain to use when calling actions on this resource. Defaults to the resource's domain."
      ],
      list_tenants: [
        type:
          {:or,
           [
             {:list, :any},
             {:spark_function_behaviour, AshOban.ListTenants, {AshOban.ListTenants.Function, 0}}
           ]},
        default: [nil],
        doc: """
        A list of tenants or a function behaviour that returns a list of tenants a trigger should be run for. Can be overwritten on the trigger level.
        """
      ]
    ],
    sections: [@triggers, @scheduled_actions]
  }

  @sections [@oban]

  @moduledoc """
  Tools for working with AshOban triggers.

  ## Module Names

  Each trigger and scheduled action must have a defined module
  name, otherwise changing the name of the trigger will lead to
  "dangling" jobs. Because Oban uses the module name to determine
  which code should execute when a job runs, changing the module name
  associated with a trigger will cause those jobs to fail and be lost
  if their worker's module name was configured. By configuring the module
  name explicitly, renaming the resource or the trigger will not cause
  an issue.

  This was an oversight in the initial design of AshOban triggers and
  scheduled actions, and in the future the module names will be required
  to ensure that this does not happen.

  Use `mix ash_oban.set_default_module_names` to set the module names to
  their appropriate default values.
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    imports: [AshOban.Changes.BuiltinChanges],
    verifiers: [
      AshOban.Verifiers.VerifyModuleNames
    ],
    transformers: [
      AshOban.Transformers.SetDefaults,
      AshOban.Transformers.DefineSchedulers,
      AshOban.Transformers.DefineActionWorkers
    ]

  @type triggerable :: Ash.Resource.t() | {Ash.Resource.t(), atom()} | Ash.Domain.t() | atom()
  @type result :: %{
          discard: non_neg_integer(),
          cancelled: non_neg_integer(),
          success: non_neg_integer(),
          failure: non_neg_integer(),
          snoozed: non_neg_integer(),
          queues_not_drained: list(atom)
        }

  @doc """
  Schedules all relevant jobs for the provided trigger or scheduled action

  ## Options

    `:actor` - the actor to set on the job. Requires configuring an actor persister.
  """
  def schedule(resource, trigger, opts \\ []) do
    case trigger do
      %AshOban.Trigger{} ->
        trigger

      %AshOban.Schedule{} ->
        trigger

      name when is_atom(name) ->
        AshOban.Info.oban_trigger(resource, name) ||
          AshOban.Info.oban_scheduled_action(resource, name)
    end
    |> case do
      %AshOban.Schedule{worker: worker} = schedule ->
        %{}
        |> store_actor(opts[:actor], schedule.actor_persister)
        |> worker.new()
        |> Oban.insert!()

      %AshOban.Trigger{scheduler: scheduler} = trigger ->
        %{}
        |> store_actor(opts[:actor], trigger.actor_persister)
        |> scheduler.new()
        |> Oban.insert!()

      _ ->
        raise ArgumentError, "Invalid trigger or scheduled action: #{inspect(trigger)}"
    end
  end

  @spec authorize? :: boolean
  def authorize? do
    Application.get_env(:ash_oban, :authorize?, true)
  end

  @spec store_actor(
          args :: map,
          actor :: any,
          actor_persister :: module() | :none | nil
        ) :: any
  def store_actor(args, actor, actor_persister \\ nil)

  def store_actor(args, nil, _actor_persister) do
    args
  end

  def store_actor(args, actor, actor_persister) do
    case actor_persister || Application.get_env(:ash_oban, :actor_persister) do
      :none ->
        args

      nil ->
        args

      persister ->
        Map.put(args, "actor", persister.store(actor))
    end
  end

  @spec lookup_actor(actor_json :: any, actor_persister :: module() | :none | nil) :: any
  def lookup_actor(actor_json, actor_persister \\ nil) do
    case actor_persister || Application.get_env(:ash_oban, :actor_persister) do
      :none ->
        {:ok, nil}

      nil ->
        {:ok, nil}

      persister ->
        persister.lookup(actor_json)
    end
  end

  @doc """
  Runs a specific trigger for the record provided.

  ## Options

  Options are passed through to `build_trigger/3` check its documentation
  for the possible values
  """
  def run_trigger(record, trigger, opts \\ []) do
    record
    |> build_trigger(trigger, opts)
    |> Oban.insert!()
  end

  @doc """
  Runs a specific trigger for the records provided.

  ## Options

  Options are passed through to `build_trigger/3` check its documentation
  for the possible values
  """
  def run_triggers(records, trigger, opts \\ []) do
    jobs =
      records
      |> Enum.map(&build_trigger(&1, trigger, opts))

    if AshOban.Info.pro?() do
      jobs
      |> Oban.insert_all()
    else
      jobs
      |> Enum.map(&Oban.insert!/1)
    end
  end

  @doc """
  Builds a specific trigger for the record provided, but does not insert it into the database.

  ## Options

  - `:actor` - the actor to set on the job. Requires configuring an actor persister.
  - `:tenant` - the tenant to set on the job.
  - `:action_arguments` - additional arguments to merge into the action invocation's arguments map.
     affects the uniqueness checks for the job.
  - `:args` - additional arguments to merge into the job's arguments map.
     the action will not use these arguments, it can only be used to affect the job uniqueness checks.
     you likely are looking for the `:action_arguments` job.

  All other options are passed through to `c:Oban.Worker.new/2`
  """
  def build_trigger(%resource{} = record, trigger, opts \\ []) do
    {opts, oban_job_opts} = Keyword.split(opts, [:actor, :tenant, :args, :action_arguments])

    trigger =
      case trigger do
        %AshOban.Trigger{} ->
          trigger

        name when is_atom(name) ->
          AshOban.Info.oban_trigger(resource, name)
      end

    primary_key = Ash.Resource.Info.primary_key(resource)

    metadata =
      case trigger do
        %{read_metadata: read_metadata} when is_function(read_metadata) ->
          read_metadata.(record)

        _ ->
          %{}
      end

    extra_args =
      case trigger.extra_args do
        nil ->
          %{}

        fun when is_function(fun) ->
          fun.(record)

        args ->
          args
      end

    %{
      primary_key: validate_primary_key(Map.take(record, primary_key), resource),
      metadata: metadata,
      action_arguments: opts[:action_arguments] || %{},
      tenant: opts[:tenant]
    }
    |> AshOban.store_actor(opts[:actor], trigger.actor_persister)
    |> then(&Map.merge(extra_args, &1))
    |> then(&Map.merge(opts[:args] || %{}, &1))
    |> trigger.worker.new(oban_job_opts)
  end

  defp validate_primary_key(map, resource) do
    Enum.each(map, fn {key, value} ->
      case value do
        %Ash.NotLoaded{} = value ->
          raise "Invalid value provided for #{inspect(resource)} primary key #{key}: #{value}"

        %Ash.ForbiddenField{} = value ->
          raise "Invalid value provided for #{inspect(resource)} primary key #{key}: #{value}"

        _ ->
          :ok
      end
    end)

    map
  end

  @config_schema [
    require?: [
      type: :boolean,
      default: true,
      doc: """
      Whether to require queues and plugins to be defined in your oban config. This can be helpful to
      allow the ability to split queues between nodes. See https://hexdocs.pm/oban/splitting-queues.html
      """
    ]
  ]

  @doc """
  Alters your oban configuration to include the required AshOban configuration.

  # Options

  #{Spark.Options.docs(@config_schema)}
  """
  def config(domains, base, opts \\ []) do
    domains = List.wrap(domains)
    opts = Spark.Options.validate!(opts, @config_schema)

    base =
      Keyword.update(base, :plugins, [], fn plugins ->
        Enum.map(plugins || [], fn item ->
          if is_atom(item) do
            {item, []}
          else
            item
          end
        end)
      end)

    pro_dynamic_cron_plugin? =
      base
      |> Keyword.get(:plugins, [])
      |> Enum.any?(fn
        {plugin, _opts} -> plugin == Oban.Pro.Plugins.DynamicCron
      end)

    pro_dynamic_queues_plugin? =
      base
      |> Keyword.get(:plugins, [])
      |> Enum.any?(fn
        {plugin, _opts} -> plugin == Oban.Pro.Plugins.DynamicQueues
      end)

    cron_plugin =
      if pro_dynamic_cron_plugin? do
        Oban.Pro.Plugins.DynamicCron
      else
        Oban.Plugins.Cron
      end

    if (pro_dynamic_cron_plugin? || pro_dynamic_queues_plugin?) &&
         base[:engine] not in [Oban.Pro.Queue.SmartEngine, Oban.Pro.Engines.Smart] do
      raise """
      Expected oban engine to be Oban.Pro.Queue.SmartEngine or Oban.Pro.Engines.Smart, but got #{inspect(base[:engine])}.
      This expectation is because you're using at least one Oban.Pro plugin`.
      """
    end

    domains
    |> Enum.flat_map(fn domain ->
      domain
      |> Ash.Domain.Info.resources()
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn resource ->
      resource
      |> AshOban.Info.oban_triggers_and_scheduled_actions()
      |> tap(fn triggers ->
        if opts[:require?] do
          Enum.each(triggers, &require_queues!(base, resource, pro_dynamic_queues_plugin?, &1))
        end
      end)
      |> Enum.filter(fn
        %{scheduler_cron: scheduler_cron} ->
          scheduler_cron

        _ ->
          true
      end)
      |> Enum.map(&{resource, &1})
    end)
    |> case do
      [] ->
        base

      resources_and_triggers ->
        if opts[:require?] do
          require_cron!(base, cron_plugin)
        end

        if pro_dynamic_cron_plugin? &&
             Enum.find_value(base[:plugins], [], fn
               {plugin, opts} -> if plugin == Oban.Pro.Plugins.DynamicCron, do: opts, else: false
             end)[:sync_mode] != :automatic do
          IO.warn("""
          The crontab `sync_mode` should be set to `:automatic`. Without this set,
          removing a trigger from your resource would cause a dangling cron job to
          exist in the database. If you don't set this, you *must* ensure that you
          *do not* remove triggers from your resource that have a `scheduler_cron`
          configured (which defaults to `* * * * *`), without first setting their
          `state` to `:deleted`, and deploying that change. After that deploy, you
          can then safely remove the trigger. i.e

              trigger do
                ...
                state :deleted
              end
          """)
        end

        resources_and_triggers
        |> Enum.reject(fn
          %{scheduler_cron: false} ->
            true

          _ ->
            false
        end)
        |> Enum.reduce(base, fn {resource, trigger}, config ->
          add_job(config, cron_plugin, resource, trigger)
        end)
    end
  end

  defp add_job(config, cron_plugin, _resource, trigger) do
    Keyword.update!(config, :plugins, fn plugins ->
      Enum.map(plugins, fn
        {^cron_plugin, config} ->
          opts =
            case {cron_plugin, trigger.state} do
              {_cron_plugin, :paused} ->
                [paused: true]

              {_cron_plugin, :deleted} ->
                [delete: true]

              {Oban.Pro.Plugins.DynamicCron, :active} ->
                [paused: false]

              _ ->
                []
            end

          cron =
            case trigger do
              %{scheduler_cron: scheduler_cron} ->
                {scheduler_cron, trigger.scheduler, opts}

              %{cron: cron} ->
                {cron, trigger.worker, opts}
            end

          {cron_plugin, Keyword.update(config, :crontab, [cron], &[cron | &1])}

        other ->
          other
      end)
    end)
  end

  defp require_queues!(config, resource, false, trigger) do
    unless config[:queues][trigger.queue] do
      raise """
      Must configure the queue `:#{trigger.queue}`, required for
      the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end

    if Map.has_key?(trigger, :scheduler_queue) do
      unless config[:queues][trigger.scheduler_queue] do
        raise """
        Must configure the queue `:#{trigger.scheduler_queue}`, required for
        the scheduler of the trigger `:#{trigger.name}` on #{inspect(resource)}
        """
      end
    end
  end

  defp require_queues!(config, resource, true, trigger) do
    {_plugin_name, plugin_config} =
      config[:plugins]
      |> Enum.find({nil, nil}, fn {plugin, _opts} -> plugin == Oban.Pro.Plugins.DynamicQueues end)

    if !is_list(plugin_config) || !Keyword.has_key?(plugin_config, :queues) ||
         !is_list(plugin_config[:queues]) ||
         !Keyword.has_key?(plugin_config[:queues], trigger.queue) do
      raise """
      Must configure the queue `:#{trigger.queue}`, required for
      the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end

    if !is_nil(config[:queues]) && config[:queues] != false do
      raise """
      Must configure the queue through Oban.Pro.Plugins.DynamicQueues plugin
      when Oban Pro is used
      """
    end

    if Map.has_key?(trigger, :scheduler_queue) do
      unless plugin_config[:queues][trigger.scheduler_queue] do
        raise """
        Must configure the queue `:#{trigger.scheduler_queue}`, required for
        the scheduler of the trigger `:#{trigger.name}` on #{inspect(resource)}
        """
      end
    end
  end

  defp require_cron!(config, name) do
    unless Enum.find(config[:plugins] || [], &match?({^name, _}, &1)) do
      ideal =
        if Keyword.keyword?(config[:plugins]) do
          Keyword.update!(config, :plugins, fn plugins ->
            Keyword.put(plugins, name, [])
          end)
        end

      ideal =
        if ideal do
          """

          Example:

          #{inspect(ideal)}
          """
        end

      raise """
      Must configure cron plugin #{inspect(name)}.

      See oban's documentation for more. AshOban will
      add cron jobs to the configuration, but will not
      add the basic configuration for you.

      Configuration received:

      #{inspect(config)}
      #{ideal}
      """
    end
  end

  @doc false
  def update_or_destroy(changeset) do
    if changeset.action.type == :update do
      Ash.update(changeset)
    else
      Ash.destroy(changeset)
    end
  end

  @doc false
  def debug(message, true) do
    Logger.debug(message)
  end

  def debug(message, false) do
    if Application.get_env(:ash_oban, :debug_all_triggers?) do
      Logger.debug(message)
    else
      :ok
    end
  end

  def stacktrace(%{stacktrace: %{stacktrace: stacktrace}}) when not is_nil(stacktrace) do
    stacktrace
  end

  def stacktrace(_), do: nil

  @doc """
  Runs the schedulers for the given resource, domain, or otp_app, or list of resources, domains, or otp_apps.

  Options:

  - `drain_queues?` - Defaults to false, drains the queues after scheduling. This is primarily for testing
  - `queue`, `with_limit`, `with_recursion`, `with_safety`, `with_scheduled` - passed through to `Oban.drain_queue/2`, if it is called
  - `scheduled_actions?` - Defaults to false, unless a scheduled action name was explicitly provided. Schedules all applicable scheduled actions.
  - `triggers?` - Defaults to true, schedules all applicable scheduled actions.
  - `actor` - The actor to schedule and run the triggers with
  - `oban` - The oban module to use. Defaults to `Oban`

  If the input is:
  * a list - each item is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * an otp_app - each domain configured in the `ash_domains` of that otp_app is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * a domain - each reosurce configured in that domain is passed into `schedule_and_run_triggers/1`, and the results are merged together.
  * a tuple of {resource, :trigger_name} - that trigger is scheduled, and the results are merged together.
  * a resource - each trigger configured in that resource is scheduled, and the results are merged together.
  """
  @spec schedule_and_run_triggers(triggerable | list(triggerable), keyword()) :: result
  def schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:scheduled_actions?, false)
      |> Keyword.put_new(:triggers?, true)
      |> Keyword.put_new(:drain_queues?, false)
      |> Keyword.put_new(:oban, Oban)

    do_schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts)
  end

  def do_schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts)
      when is_list(resources_or_domains_or_otp_apps) do
    Enum.reduce(resources_or_domains_or_otp_apps, default_acc(), fn item, acc ->
      item
      |> do_schedule_and_run_triggers(opts)
      |> merge_results(acc)
    end)
  end

  def do_schedule_and_run_triggers({resource, trigger_name}, opts) do
    triggers =
      resource
      |> AshOban.Info.oban_triggers_and_scheduled_actions()
      |> Enum.filter(fn
        %AshOban.Schedule{name: name} ->
          name == trigger_name

        trigger ->
          trigger.scheduler && trigger.name == trigger_name
      end)

    Enum.each(triggers, fn trigger ->
      AshOban.schedule(resource, trigger, actor: opts[:actor])
    end)

    queues =
      triggers
      |> Enum.map(& &1.queue)
      |> Enum.uniq()

    # we drain each queue twice to do schedulers and then workers
    drain_queues(queues, opts)
  end

  def do_schedule_and_run_triggers(resource_or_domain_or_otp_app, opts) do
    cond do
      Spark.Dsl.is?(resource_or_domain_or_otp_app, Ash.Domain) ->
        resource_or_domain_or_otp_app
        |> Ash.Domain.Info.resources()
        |> Enum.reduce(%{}, fn resource, acc ->
          resource
          |> do_schedule_and_run_triggers(opts)
          |> merge_results(acc)
        end)

      Spark.Dsl.is?(resource_or_domain_or_otp_app, Ash.Resource) ->
        triggers =
          resource_or_domain_or_otp_app
          |> AshOban.Info.oban_triggers_and_scheduled_actions()
          |> Enum.filter(fn
            %AshOban.Schedule{} ->
              opts[:scheduled_actions?] && true

            trigger ->
              trigger.scheduler
          end)

        Enum.each(triggers, fn trigger ->
          AshOban.schedule(resource_or_domain_or_otp_app, trigger, actor: opts[:actor])
        end)

        queues =
          triggers
          |> Enum.map(& &1.queue)
          |> Enum.uniq()

        # we drain each queue twice to do schedulers and then workers
        drain_queues(queues, opts)

      true ->
        resource_or_domain_or_otp_app
        |> Application.get_env(:ash_domains, [])
        |> List.wrap()
        |> Enum.reduce(default_acc(), fn domain, acc ->
          domain
          |> do_schedule_and_run_triggers(opts)
          |> merge_results(acc)
        end)
    end
  end

  defp drain_queues(queues, opts) do
    if opts[:drain_queues?] do
      Enum.reduce(queues ++ queues, default_acc(), fn queue, acc ->
        [queue: queue]
        |> Keyword.merge(
          Keyword.take(opts, [
            :queue,
            :with_limit,
            :with_recursion,
            :with_safety,
            :with_scheduled
          ])
        )
        |> drain_queue()
        |> Map.put(:queues_not_drained, [])
        |> merge_results(acc)
      end)
    else
      default_acc()
      |> Map.update!(:queues_not_drained, &Enum.uniq(&1 ++ queues))
    end
  end

  defp drain_queue(opts) do
    oban = opts[:oban] || Oban

    config = Oban.config(oban)

    if config.testing == :disabled do
      raise ArgumentError, """
      Cannot use the `drain_queues?: true` option outside of the test environment, unless you are also using oban pro.

      For more information, see this github issue: https://github.com/sorentwo/oban/issues/1037#issuecomment-1962928460
      """
    else
      Oban.drain_queue(opts)
    end
  end

  defp default_acc do
    %{
      discard: 0,
      cancelled: 0,
      success: 0,
      failure: 0,
      snoozed: 0,
      queues_not_drained: []
    }
  end

  defp merge_results(results, acc) do
    Map.merge(results, acc, fn
      :queues_not_drained, left, right ->
        Enum.uniq(left ++ right)

      _key, left, right ->
        left + right
    end)
  end
end
