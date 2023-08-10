defmodule AshOban.Transformers.SetDefaults do
  @moduledoc "Set trigger default values"

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(AshOban.Transformers.DefineSchedulers), do: false
  def after?(_), do: true
  def before?(AshOban.Transformers.DefineSchedulers), do: true
  def before?(_), do: false

  # sobelow_skip ["DOS.BinToAtom"]
  def transform(dsl) do
    module = Transformer.get_persisted(dsl, :module)

    {:ok,
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
           cron?: if(is_nil(trigger.cron?), do: true, else: trigger.cron?)
       })
     end)}
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp default_queue_name(dsl, trigger) do
    :"#{Ash.Resource.Info.short_name(dsl)}_#{trigger.name}"
  end
end
