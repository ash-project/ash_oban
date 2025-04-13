defmodule AshOban.Igniter do
  @moduledoc "Codemods and utilities for resources that use `AshOban`."
  @doc "Adds the given code block to the resource's `triggers` block if there is no existing trigger with the given name"
  def add_new_trigger(igniter, resource, name, trigger) do
    {igniter, defines?} = defines_trigger(igniter, resource, name)

    if defines? do
      igniter
    else
      add_trigger(igniter, resource, trigger)
    end
  end

  @doc "Adds the given code block to the resource's `triggers` block"
  def add_trigger(igniter, resource, trigger) do
    Igniter.Project.Module.find_and_update_module!(igniter, resource, fn zipper ->
      with {:oban, {:ok, zipper}} <-
             {:oban,
              Igniter.Code.Function.move_to_function_call_in_current_scope(
                zipper,
                :oban,
                1
              )},
           {:oban, {:ok, oban_zipper}} <- {:oban, Igniter.Code.Common.move_to_do_block(zipper)},
           {:triggers, oban_zipper, {:ok, zipper}} <-
             {:triggers, oban_zipper,
              Igniter.Code.Function.move_to_function_call_in_current_scope(
                oban_zipper,
                :triggers,
                1
              )},
           {:triggers, _oban_zipper, {:ok, zipper}} <-
             {:triggers, oban_zipper, Igniter.Code.Common.move_to_do_block(zipper)} do
        {:ok, Igniter.Code.Common.add_code(zipper, trigger)}
      else
        {:oban, :error} ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           oban do
             triggers do
               #{trigger}
             end
           end
           """)}

        {:triggers, oban_zipper, :error} ->
          {:ok,
           Igniter.Code.Common.add_code(oban_zipper, """
            triggers do
              #{trigger}
            end
           """)}
      end
    end)
  end

  @doc "Returns true if the given resource defines a trigger with the provided name"
  @spec defines_trigger(Igniter.t(), Ash.Resource.t(), atom()) :: {Igniter.t(), true | false}
  def defines_trigger(igniter, resource, name) do
    Spark.Igniter.find(igniter, resource, fn _, zipper ->
      with {:ok, zipper} <- enter_section(zipper, :oban),
           {:ok, zipper} <- enter_section(zipper, :triggers),
           {:ok, _zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :trigger,
               2,
               &Igniter.Code.Function.argument_equals?(&1, 0, name)
             ) do
        {:ok, true}
      else
        _ ->
          :error
      end
    end)
    |> case do
      {:ok, igniter, _module, _value} ->
        {igniter, true}

      {:error, igniter} ->
        {igniter, false}
    end
  end

  defp enter_section(zipper, name) do
    with {:ok, zipper} <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             name,
             1
           ) do
      Igniter.Code.Common.move_to_do_block(zipper)
    end
  end
end
