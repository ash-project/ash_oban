defmodule AshOban.Changes.BuiltinChanges do
  @moduledoc "Builtin changes for `AshOban`"

  def run_oban_trigger(trigger_name) do
    {AshOban.Changes.RunObanTrigger, trigger: trigger_name}
  end
end
