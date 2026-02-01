# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshOban.Upgrade do
    @moduledoc false

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_oban,
        positional: [:from, :to]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      positional = igniter.args.positional
      options = igniter.args.options

      upgrades =
        %{
          "0.4.0" => [&set_default_module_names/2]
        }

      # For each version that requires a change, add it to this map
      # Each key is a version that points at a list of functions that take an
      # igniter and options (i.e. flags or other custom options).
      # See the upgrades guide for more.
      Igniter.Upgrades.run(igniter, positional.from, positional.to, upgrades,
        custom_opts: options
      )
    end

    defp set_default_module_names(zipper, _) do
      Igniter.compose_task(zipper, "ash_oban.set_default_module_names")
    end
  end
else
  defmodule Mix.Tasks.AshOban.Upgrade do
    @moduledoc false

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_oban.upgrade' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
