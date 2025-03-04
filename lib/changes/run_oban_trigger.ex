defmodule AshOban.Changes.RunObanTrigger do
  @moduledoc """
  Runs an oban trigger by name.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    trigger = AshOban.Info.oban_trigger(changeset.resource, opts[:trigger])

    if !trigger do
      raise "No such trigger #{opts[:trigger]} for resource #{inspect(changeset.resource)}"
    end

    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      AshOban.run_trigger(
        result,
        trigger,
        Keyword.merge(
          opts[:oban_job_opts] || [],
          context
          |> Ash.Context.to_opts()
          |> Keyword.take([:actor, :tenant])
        )
      )

      {:ok, result}
    end)
  end

  @impl true
  def batch_change(changesets, _opts, _context) do
    changesets
  end

  @impl true
  def atomic(changeset, opts, context) do
    {:ok, change(changeset, opts, context)}
  end

  @impl true
  def after_batch([{changeset, _} | _] = changesets_and_results, opts, context) do
    trigger = AshOban.Info.oban_trigger(changeset.resource, opts[:trigger])

    if !trigger do
      raise "No such trigger #{opts[:trigger]} for resource #{inspect(changeset.resource)}"
    end

    results =
      changesets_and_results
      |> Enum.map(&elem(&1, 1))

    results
    |> AshOban.run_triggers(
      trigger,
      Keyword.merge(
        opts[:oban_job_opts] || [],
        context
        |> Ash.Context.to_opts()
        |> Keyword.take([:actor, :tenant])
      )
    )

    results
    |> Enum.map(&{:ok, &1})
  end
end
