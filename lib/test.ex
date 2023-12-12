defmodule AshOban.Test do
  @moduledoc "Helpers for testing ash_oban triggers"

  defdelegate schedule_and_run_triggers(resources_or_apis_or_otp_apps, opts \\ []), to: AshOban
end
