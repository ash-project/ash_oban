# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Changes.BuiltinChanges do
  @moduledoc "Builtin changes for `AshOban`"

  def run_oban_trigger(trigger_name, oban_job_opts \\ []) do
    {AshOban.Changes.RunObanTrigger, trigger: trigger_name, oban_job_opts: oban_job_opts}
  end
end
