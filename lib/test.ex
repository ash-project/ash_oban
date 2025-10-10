# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  @doc """
  Calls `AshOban.schedule_and_run_triggers/2` with `drain_queues?: true`.
  """
  def schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts \\ []) do
    opts = Keyword.put_new(opts, :drain_queues?, true)
    AshOban.schedule_and_run_triggers(resources_or_domains_or_otp_apps, opts)
  end
end
