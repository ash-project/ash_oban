defmodule Mix.Tasks.AshOban.SetDefaultModuleNames.Docs do
  @moduledoc false

  def short_doc do
    "Set module names to their default values for triggers and scheduled actions"
  end

  def example do
    "mix ash_oban.set_default_module_names"
  end

  def long_doc do
    """
    #{short_doc()}

    Each trigger must have a defined module name, otherwise changing
    the name of the trigger will lead to "dangling" jobs. See the
    `AshOban` documentation for more.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshOban.SetDefaultModuleNames do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_oban,
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      # Do your work here and return an updated igniter
      {igniter, resources} = Ash.Resource.Igniter.list_resources(igniter)

      Enum.reduce(resources, igniter, fn resource, igniter ->
        igniter
        |> Igniter.Project.Module.find_and_update_module!(resource, fn zipper ->
          replace_trigger_worker_module(
            zipper,
            :triggers,
            :trigger,
            :worker_module_name,
            &module_name(resource, &1, "Worker")
          )
        end)
        |> Igniter.Project.Module.find_and_update_module!(resource, fn zipper ->
          replace_trigger_worker_module(
            zipper,
            :triggers,
            :trigger,
            :scheduler_module_name,
            &module_name(resource, &1, "Scheduler")
          )
        end)
        |> Igniter.Project.Module.find_and_update_module!(resource, fn zipper ->
          replace_trigger_worker_module(
            zipper,
            :scheduled_actions,
            :schedule,
            :worker_module_name,
            &module_name(resource, &1, "Scheduler")
          )
        end)
      end)
    end

    defp replace_trigger_worker_module(zipper, section_name, entity_name, option_name, setter) do
      with {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :oban, 1),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               section_name,
               1
             ),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
        Igniter.Code.Common.update_all_matches(
          zipper,
          fn zipper ->
            with {:ok, zipper} <-
                   Igniter.Code.Function.move_to_function_call_in_current_scope(
                     zipper,
                     entity_name,
                     2
                   ),
                 {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
                 :error <-
                   Igniter.Code.Function.move_to_function_call_in_current_scope(
                     zipper,
                     option_name,
                     1
                   ) do
              true
            else
              _ ->
                false
            end
          end,
          fn zipper ->
            with {:ok, zipper} <-
                   Igniter.Code.Function.move_to_function_call_in_current_scope(
                     zipper,
                     entity_name,
                     2
                   ),
                 {:ok, name_zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0),
                 {:ok, name} <- Igniter.Code.Common.expand_literal(name_zipper),
                 {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
              {:ok,
               Igniter.Code.Common.add_code(zipper, """
               #{option_name} #{inspect(setter.(name))}
               """)}
            else
              _ ->
                {:ok, zipper}
            end
          end
        )
      else
        _ ->
          {:ok, zipper}
      end
    end

    defp module_name(module, name, type) do
      module
      |> List.wrap()
      |> Enum.concat(["AshOban", type])
      |> Enum.concat([Macro.camelize(to_string(name))])
      |> Module.concat()
    end
  end
else
  defmodule Mix.Tasks.AshOban.SetDefaultModuleNames do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_oban.set_default_module_names' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
