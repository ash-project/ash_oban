defmodule AshOban do
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
            max_attempts: pos_integer(),
            record_limit: pos_integer(),
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
      :worker_read_action,
      :queue,
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
    imports: [Ash.Filter.TemplateHelpers],
    transform: {Trigger, :transform, []},
    schema: [
      name: [
        type: :atom,
        doc: "A unique identifier for this trigger."
      ],
      scheduler_queue: [
        type: :atom,
        doc:
          "The queue to place the scheduler job in. The same queue as job is used by default (but with a priority of 1 so schedulers run first)."
      ],
      scheduler_cron: [
        type: {:or, [:string, {:literal, false}]},
        default: "* * * * *",
        doc: """
        A crontab configuration for when the job should run. Defaults to once per minute (\"* * * * *\").
        Use `false` to disable the scheduler entirely.
        """
      ],
      stream_batch_size: [
        type: :pos_integer,
        doc:
          "The batch size to pass when streaming records from using `Ash.Api.stream/2`. No batch size is passed if none is provided here, so the default is used."
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
        How many times to attempt the job.

        Keep in mind: after all of these attempts, the scheduler will likely just reschedule the job,
        leading to infinite retries. To solve for this, configure an `on_error` action that will make
        the trigger no longer apply to failed jobs.
        """
      ],
      read_metadata: [
        type: {:fun, 1},
        doc: """
        Takes a record, and returns additional data of records from the read action.
        This metadata will be stored in the database and serialized to json before
        being passed to the update action as an argument called `metadata`.
        """
      ],
      state: [
        type: {:one_of, [:active, :paused, :deleted]},
        default: :active,
        doc: """
        Describes the state of the cron job.

        See the getting started guide for an explanation on the need for this field.
        The most important thing is that you *do not remove a trigger from a resource*.
        Oban's cron jobs are persisted, meaning you will get repeated errors whenever the cron
        job tries to fire.
        """
      ],
      read_action: [
        type: :atom,
        doc: """
        The read action to use when querying records. Defaults to the primary read.

        This action *must* support keyset pagination.
        """
      ],
      worker_read_action: [
        type: :atom,
        doc: """
        The read action to use when fetching the individual records for the trigger.

        This defaults to `read_action`, allowing us to discard records that are no longer relevant.
        You may need to change this, and if so make sure your action handles the scenario where the
        trigger is no longer relevant.
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

  @triggers %Spark.Dsl.Section{
    name: :triggers,
    entities: [@trigger]
  }

  @oban %Spark.Dsl.Section{
    name: :oban,
    schema: [
      api: [
        type: {:behaviour, Ash.Api},
        doc: "The Api module to use when calling actions on this resource",
        required: true
      ]
    ],
    sections: [@triggers]
  }

  @sections [@oban]

  @moduledoc """
  Dsl documentation for AshOban
  <!--- ash-hq-hide-start --> <!--- -->

  ## DSL Documentation

  ### Index

  #{Spark.Dsl.Extension.doc_index(@sections)}

  ### Docs

  #{Spark.Dsl.Extension.doc(@sections)}
  <!--- ash-hq-hide-stop --> <!--- -->
  """

  use Spark.Dsl.Extension,
    sections: [@oban],
    imports: [AshOban.Changes.BuiltinChanges],
    transformers: [
      AshOban.Transformers.SetDefaults,
      AshOban.Transformers.DefineSchedulers
    ]

  def schedule(resource, trigger) do
    trigger =
      case trigger do
        %AshOban.Trigger{} ->
          trigger

        name when is_atom(name) ->
          AshOban.Info.oban_trigger(resource, name)
      end

    %{}
    |> trigger.scheduler.new()
    |> Oban.insert!()
  end

  def run_trigger(%resource{} = record, trigger, oban_job_opts) do
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

    %{primary_key: Map.take(record, primary_key), metadata: metadata}
    |> trigger.worker.new(oban_job_opts)
    |> Oban.insert!()
  end

  @doc "Alters your oban configuration to include the required AshOban configuration."
  def config(apis, base) do
    pro? = AshOban.Info.pro?()

    cron_plugin =
      if pro? do
        Oban.Pro.Plugins.DynamicCron
      else
        Oban.Plugins.Cron
      end

    if pro? && base[:engine] not in [Oban.Pro.Queue.SmartEngine, Oban.Pro.Engines.Smart] do
      raise """
      Expected oban engine to be Oban.Pro.Queue.SmartEngine or Oban.Pro.Engines.Smart, but got #{inspect(base[:engine])}.
      This expectation is because you've set `config :ash_oban, pro?: true`.
      """
    end

    require_cron!(base, cron_plugin)

    apis
    |> Enum.flat_map(fn api ->
      api
      |> Ash.Api.Info.resources()
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn resource ->
      resource
      |> AshOban.Info.oban_triggers()
      |> Enum.filter(& &1.scheduler_cron)
      |> Enum.map(&{resource, &1})
    end)
    |> Enum.reduce(base, fn {resource, trigger}, config ->
      require_queues!(config, resource, trigger)

      add_job(config, cron_plugin, resource, trigger)
    end)
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

          cron = {trigger.scheduler_cron, trigger.scheduler, opts}
          {cron_plugin, Keyword.update(config, :crontab, [cron], &[cron | &1])}

        other ->
          other
      end)
    end)
  end

  defp require_queues!(config, resource, trigger) do
    unless config[:queues][trigger.queue] do
      raise """
      Must configure the queue `:#{trigger.queue}`, required for
      the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end

    unless config[:queues][trigger.scheduler_queue] do
      raise """
      Must configure the queue `:#{trigger.scheduler_queue}`, required for
      the scheduler of the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end
  end

  defp require_cron!(config, name) do
    unless Enum.find(config[:plugins] || [], &match?({^name, _}, &1)) do
      raise """
      Must configure cron plugin #{name}.

      See oban's documentation for more. AshOban will
      add cron jobs to the configuration, but will not
      add the basic configuration for you.

      Configuration received:

      #{inspect(config)}
      """
    end
  end
end
