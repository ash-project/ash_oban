# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Signals.Worker do
  @moduledoc """
  Runs a listener for a signal stored in a job by `AshOban.Signals`.

  Listeners with `chunks` use a chunk worker defined on their resource instead, which runs the
  listener once for every signal in a chunk.
  """

  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    case run([job]) do
      :ok -> :ok
      {:error, error} -> oban_result(error)
    end
  end

  @doc false
  # Called by chunk workers, with jobs for the same listener, actor, tenant, `authorize?` and
  # signal path.
  def process_chunk(jobs) do
    case run(jobs) do
      :ok ->
        :ok

      {:error, error} ->
        case oban_result(error) do
          {:error, error} -> {:error, error, jobs}
          {:snooze, period} -> {:snooze, period, jobs}
          {:cancel, reason} -> {:cancel, reason, jobs}
        end
    end
  end

  defp run([%Oban.Job{args: args} = job | _] = jobs) do
    with {:ok, listener} <- fetch_listener(args),
         opts = delivery_options(listener),
         {:ok, stored} <- upgrade(Enum.map(jobs, & &1.args["payload"]), opts[:upgrader]),
         {:ok, signals} <- Ash.Signals.load(listener.signal_module, listener.signal, stored),
         # jobs inserted before signal paths were stored don't have one
         signal_path = Ash.Signals.load_signal_path(args["signal_path"] || []),
         {:ok, actor} <- AshOban.lookup_actor(args["actor"], opts[:actor_persister]) do
      Ash.Signals.run_listener(listener, signals,
        actor: actor,
        tenant: args["tenant"],
        authorize?: args["authorize?"],
        context:
          opts[:shared_context]
          |> AshOban.build_context(job)
          |> Map.put(:signal_path, signal_path)
      )
    end
  end

  defp oban_result(error) do
    AshOban.check_for_oban_return(Ash.Error.to_ash_error(error)) || {:error, error}
  end

  # The resource's module name is an existing atom, but its listener's name may not be until the
  # resource is loaded, so listeners are matched by name.
  defp fetch_listener(args) do
    with {:ok, resource} <- existing_atom(args["resource"]),
         true <- Code.ensure_loaded?(resource) && Ash.Resource.Info.resource?(resource),
         %{} = listener <-
           Enum.find(
             Ash.Resource.Info.signal_listeners(resource),
             &(Atom.to_string(&1.name) == args["listener"])
           ) do
      if Atom.to_string(listener.signal_module) == args["signal_module"] and
           Atom.to_string(listener.signal) == args["signal"] do
        {:ok, listener}
      else
        {:error,
         "The listener `#{args["listener"]}` of #{args["resource"]} no longer listens to `#{args["signal"]}` from #{args["signal_module"]}."}
      end
    else
      _ ->
        {:error, "There is no listener `#{args["listener"]}` on #{args["resource"]}."}
    end
  end

  defp existing_atom(string) when is_binary(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  defp existing_atom(_), do: :error

  # The listener may have changed its delivery since the job was inserted.
  defp delivery_options(listener) do
    case listener.delivery do
      {AshOban.Signals, opts} -> AshOban.Signals.options!(opts)
      _ -> []
    end
  end

  defp upgrade(stored, nil), do: {:ok, stored}

  defp upgrade(stored, {upgrader, opts}) do
    stored
    |> Enum.reduce_while({:ok, []}, fn signal, {:ok, upgraded} ->
      case upgrader.upgrade(signal, opts) do
        {:ok, signal} -> {:cont, {:ok, [signal | upgraded]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, upgraded} -> {:ok, Enum.reverse(upgraded)}
      {:error, error} -> {:error, error}
    end
  end
end
