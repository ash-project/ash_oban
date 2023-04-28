defmodule AshOban.Changes.RunObanTrigger do
  use Ash.Resource.Change

  def change(changeset, opts, _context) do
    trigger = AshOban.Info.oban_trigger(changeset.resource, opts[:trigger])
    primary_key = Ash.Resource.Info.primary_key(changeset.resource)

    if !trigger do
      raise "No such trigger #{opts[:trigger]} for resource #{inspect(changeset.resource)}"
    end

    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      %{primary_key: Map.take(result, primary_key)}
      |> trigger.worker.new()
      |> Oban.insert!()

      {:ok, result}
    end)
  end
end
