# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Repo do
  use AshPostgres.Repo, otp_app: :ash_oban, warn_on_missing_ash_functions?: false

  def installed_extensions, do: []

  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
