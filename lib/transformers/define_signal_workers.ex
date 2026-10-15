# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Transformers.DefineSignalWorkers do
  # Defines an Oban Pro chunk worker for each signal listener delivered by `AshOban.Signals`
  # with `chunks`. It's defined here, in the listener's resource, because Oban Pro may not be
  # compiled before AshOban.
  @moduledoc false

  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl) do
    if AshOban.Info.pro?() do
      resource = Transformer.get_persisted(dsl, :module)

      for %{listeners: listeners} <- Transformer.get_entities(dsl, [:signals_in]),
          %{delivery: {AshOban.Signals, opts}} = listener <- listeners,
          {:ok, opts} <- [AshOban.Signals.validate(opts)],
          opts[:chunks] do
        define_chunk_worker(resource, listener, opts)
      end
    end

    {:ok, dsl}
  end

  defp define_chunk_worker(resource, listener, opts) do
    Module.create(
      AshOban.Signals.chunk_worker(resource, listener.name),
      quote location: :keep, generated: true do
        use Oban.Pro.Workers.Chunk,
          queue: unquote(opts[:queue]),
          size: unquote(opts[:chunks][:size]),
          timeout: unquote(opts[:chunks][:timeout]),
          by: [:worker, args: [:actor, :tenant, :authorize?, :signal_path]]

        def process(jobs), do: AshOban.Signals.Worker.process_chunk(jobs)
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
