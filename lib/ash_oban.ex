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
            max_scheduler_attempts: pos_integer(),
            where: Ash.Expr.t(),
            scheduler: module,
            state: :active | :paused | :deleted,
            worker: module,
            __identifier__: atom
          }

    defstruct [
      :name,
      :action,
      :read_action,
      :queue,
      :scheduler_cron,
      :scheduler_queue,
      :max_attempts,
      :max_scheduler_attempts,
      :where,
      :state,
      :scheduler,
      :worker,
      :__identifier__
    ]
  end

  @trigger %Spark.Dsl.Entity{
    name: :trigger,
    target: Trigger,
    args: [:name],
    identifier: :name,
    imports: [Ash.Filter.TemplateHelpers],
    schema: [
      name: [
        type: :atom,
        doc: "A unique identifier for this trigger."
      ],
      scheduler_queue: [
        type: :atom,
        doc:
          "The queue to place the scheduler job in. The trigger name plus \"_scheduler\" is used by default."
      ],
      scheduler_cron: [
        type: :string,
        default: "* * * * *",
        doc:
          "A crontab configuration for when the job should run. Defaults to once per minute (\"* * * * *\")."
      ],
      queue: [
        type: :atom,
        doc: "The queue to place the worker job in. The trigger name is used by default."
      ],
      max_scheduler_attempts: [
        type: :pos_integer,
        default: 1,
        doc: "How many times to attempt scheduling of the triggered action."
      ],
      max_attempts: [
        type: :pos_integer,
        default: 1,
        doc: "How many times to attempt the job."
      ],
      state: [
        type: {:one_of, [:active, :paused, :deleted]},
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
      action: [
        type: :atom,
        required: true,
        doc:
          "The action to be triggered. Defaults to the identifier of the resource plus the name of the trigger"
      ],
      where: [
        type: :any,
        doc: "The filter expression to determine if something should be triggered"
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

  def config(apis, base \\ %{}) do
    pro? = AshOban.Info.pro?()

    cron_plugin =
      if pro? do
        Oban.Pro.Plugins.DynamicCron
      else
        Oban.Pro.Plugins.Cron
      end

    if pro? && base[:engine] != Oban.Pro.Queue.SmartEngine do
      raise """
      Expected oban engine to be Oban.Pro.Queue.SmartEngine, but got #{inspect(base[:engine])}.
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
      |> Enum.map(&{resource, &1})
    end)
    |> Enum.reduce(base, fn {resource, trigger}, config ->
      require_queues!(config, resource, trigger)
      add_job(config, cron_plugin, resource, trigger)
    end)
  end

  defp add_job(config, cron_plugin, _resource, trigger) do
    Keyword.update!(config, :plugins, fn plugins ->
      Keyword.update!(plugins, cron_plugin, fn plugins ->
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
        Keyword.update(plugins, :crontab, [cron], &[cron | &1])
      end)
    end)
  end

  defp require_queues!(config, resource, trigger) do
    unless config[:queues][trigger.queue] do
      raise """
      Must configure the queue `:#{trigger.queue}`, requied for
      the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end

    unless config[:queues][trigger.scheduler_queue] do
      raise """
      Must configure the queue `:#{trigger.queue}`, required for
      the scheduler of the trigger `:#{trigger.name}` on #{inspect(resource)}
      """
    end
  end

  defp require_cron!(config, name) do
    unless config[:plugins][name] do
      raise """
      Must configure cron plugin #{name}.

      See oban's documentation for more. AshOban will
      add cron jobs to the configuration, but will not
      add the basic configuration for you.
      """
    end
  end
end
