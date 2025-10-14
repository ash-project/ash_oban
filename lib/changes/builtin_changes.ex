# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Changes.BuiltinChanges do
  @moduledoc "Builtin changes for `AshOban`"

  def run_oban_trigger(trigger_name, oban_job_opts \\ []) do
    {AshOban.Changes.RunObanTrigger, trigger: trigger_name, oban_job_opts: oban_job_opts}
  end
end
