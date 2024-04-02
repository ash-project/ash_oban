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
            action_input: map(),
            max_attempts: pos_integer(),
            record_limit: pos_integer(),
            log_final_error?: boolean(),
            log_errors?: boolean(),
            debug?: boolean(),
            max_scheduler_attempts: pos_integer(),
            read_metadata: (Ash.Resource.record() -> map),
            stream_batch_size: pos_integer(),
            scheduler_priority: non_neg_integer(),
            worker_priority: non_neg_integer(),
            where: Ash.Expr.t(),
            scheduler: module | nil,
            state: :active | :paused | :deleted,
            worker: module,
            __identifier__: atom,
            on_error: atom
          }

    defstruct [
      :name,
      :action,
      :read_action,
      :action_input,
      :worker_read_action,
      :queue,
      :debug?,
      :read_metadata,
      :scheduler_cron,
      :scheduler_queue,
      :scheduler_priority,
      :worker_priority,
      :max_attempts,
      :stream_batch_size,
      :max_scheduler_attempts,
      :record_limit,
      :where,
      :state,
      :scheduler,
      :worker,
      :on_error,
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
      scheduler_queue: [
        type: :atom,
        doc:
          "The queue to place the scheduler job in. The same queue as job is used by default (but with a priority of 1 so schedulers run first)."
      ],
      debug?: [
        type: :boolean,
        default: false,
        doc:
          "If set to `true`, detailed debug logging will be enabled for this trigger. You can also set `config :ash_oban, debug_all_triggers?: true` to enable debug logging for all triggers."
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
          "The batch size to pass when streaming records from using `c:Ash.stream!/2`. No batch size is passed if none is provided here, so the default is used."
      ],
      queue: [
        type: :atom,
        doc: "The queue to place the worker job in. The trigger name is used by default."
      ],
      record_limit: [
        type: :pos_integer,
        doc:
          "If set, any given run of the scheduler will only ever schedule this many items maximum"
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
      on_error: [
        type: :atom,
        doc:
          "An update action to call after the last attempt has failed. See the getting started guide for more."
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
            max_attempts: non_neg_integer(),
            queue: atom,
            debug?: boolean,
            state: :active | :paused | :deleted,
            priority: non_neg_integer()
          }

    defstruct [
      :name,
      :action,
      :cron,
      :debug,
      :priority,
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
      ]
    ],
    sections: [@triggers, @scheduled_actions]
  }

  @sections [@oban]

  @moduledoc """
  Tools for working with AshOban triggers.
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    imports: [AshOban.Changes.BuiltinChanges],
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
      %AshOban.Schedule{worker: worker} ->
        %{}
        |> store_actor(opts[:actor])
        |> worker.new()
        |> Oban.insert!()

      %AshOban.Trigger{scheduler: scheduler} ->
        %{}
        |> store_actor(opts[:actor])
        |> scheduler.new()
        |> Oban.insert!()
    end
  end

  @spec authorize? :: boolean
  def authorize? do
    Application.get_env(:ash_oban, :authorize?, true)
  end

  @spec store_actor(args :: map, actor :: any) :: any
  def store_actor(args, nil), do: args

  def store_actor(args, actor) do
    case Application.get_env(:ash_oban, :actor_persister) do
      nil ->
        args

      persister ->
        Map.put(args, "actor", persister.store(actor))
    end
  end

  @spec lookup_actor(actor_json :: any) :: any
  def lookup_actor(actor_json) do
    case Application.get_env(:ash_oban, :actor_persister) do
      nil ->
        {:ok, nil}

      persister ->
        persister.lookup(actor_json)
    end
  end

  @doc """
  Runs a specific trigger for the record provided.

  ## Options

  - `:actor` - the actor to set on the job. Requires configuring an actor persister.

  All other options are passed through to `c:Oban.Worker.new/2`
  """
  def run_trigger(record, trigger, opts \\ []) do
    record
    |> build_trigger(trigger, opts)
    |> Oban.insert!()
  end

  @doc """
  Builds a specific trigger for the record provided, but does not insert it into the database.

  ## Options

  - `:actor` - the actor to set on the job. Requires configuring an actor persister.

  All other options are passed through to `c:Oban.Worker.new/2`
  """
  def build_trigger(%resource{} = record, trigger, opts \\ []) do
    {opts, oban_job_opts} = Keyword.split(opts, [:actor])

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

    %{
      primary_key: validate_primary_key(Map.take(record, primary_key), resource),
      metadata: metadata
    }
    |> AshOban.store_actor(opts[:actor])
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
    ],
    pro?: [
      type: :boolean,
      default: false,
      doc: """
      If you are using Oban Pro, set this to true
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
    pro? = AshOban.Info.pro?()

    cron_plugin =
      if opts[:pro?] do
        Oban.Pro.Plugins.DynamicCron
      else
        Oban.Plugins.Cron
      end

    if opts[:pro?] && base[:engine] not in [Oban.Pro.Queue.SmartEngine, Oban.Pro.Engines.Smart] do
      raise """
      Expected oban engine to be Oban.Pro.Queue.SmartEngine or Oban.Pro.Engines.Smart, but got #{inspect(base[:engine])}.
      This expectation is because you've called AshOban.config\3 with `pro?: true`.
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
          Enum.each(triggers, &require_queues!(base, resource, opts[:pro?], &1))
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

        Enum.reduce(resources_and_triggers, base, fn {resource, trigger}, config ->
          add_job(config, cron_plugin, resource, trigger)
        end)
    end
  end

  defp add_job(config, cron_plugin, _resource, trigger) do
    Keyword.update!(config, :plugins, fn plugins ->
      Enum.map(plugins, fn
        {^cron_plugin, config} ->
          opts =
            case trigger.state do
              :paused ->
                [paused: true]

              :deleted ->
                [delete: true]

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

    if !is_list(plugin_config) || !Keyword.has_key?(plugin_config, :queues) || !is_list(plugin_config[:queues]) || !Keyword.has_key?(plugin_config[:queues], trigger.queue) do
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
