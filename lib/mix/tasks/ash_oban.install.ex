defmodule Mix.Tasks.AshOban.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs AshOban and Oban"
  end

  def example do
    "mix igniter.install ash_oban"
  end

  def long_doc do
    """
    #{short_doc()}

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshOban.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :ash,
        # dependencies to add
        adds_deps: [],
        # dependencies to add and call their associated installers, if they exist
        installs: [
          {:oban, "~> 2.0"}
        ],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # A list of environments that this should be installed in.
        only: nil,
        # a list of positional arguments, i.e `[:file]`
        positional: [],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [],
        # `OptionParser` schema
        schema: [],
        # Default values for the options in the `schema`
        defaults: [],
        # CLI aliases
        aliases: [],
        # A list of options in the schema that are required
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      pro? = Igniter.Project.Deps.has_dep?(igniter, :oban_pro)

      cron_plugin = if pro?, do: Oban.Plugins.Cron, else: Oban.Pro.Plugins.DynamicCron

      # Do your work here and return an updated igniter
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_oban)
      |> Igniter.Project.Application.add_new_child(
        {Oban,
         {:code,
          """
          AshOban.config(
            Application.fetch_env!(:#{app_name}, :ash_domains),
            Application.fetch_env!(:#{app_name}, Oban)
          )
          """
          |> Sourceror.parse_string!()}},
        opts_updater: fn zipper ->
          case Igniter.Code.Function.move_to_function_call(zipper, {AshOban, :config}, [1, 2]) do
            {:ok, zipper} ->
              {:ok, zipper}

            :error ->
              new_code =
                quote do
                  AshOban.config(
                    Application.fetch_env!(unquote(app_name), :ash_domains),
                    unquote(zipper.node)
                  )
                end
                |> Sourceror.to_string()
                |> Sourceror.parse_string!()

              {:ok, Igniter.Code.Common.replace_code(zipper, new_code)}
          end
        end
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        app_name,
        [Oban, :plugins],
        [{cron_plugin, []}],
        updater: fn list ->
          case Igniter.Code.List.prepend_new_to_list(list, {cron_plugin, []}, fn old, new ->
                 if Igniter.Code.Tuple.tuple?(old) do
                   with {:ok, plugin} <- Igniter.Code.Tuple.tuple_elem(old, 0) do
                     Igniter.Code.Common.nodes_equal?(plugin, cron_plugin)
                   end
                 else
                   Igniter.Code.Common.nodes_equal?(old, new)
                 end
               end) do
            {:ok, list} -> {:ok, list}
            :error -> {:ok, list}
          end
        end
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        :ash_oban,
        [:pro?],
        pro?
      )
    end
  end
else
  defmodule Mix.Tasks.AshOban.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_oban.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
