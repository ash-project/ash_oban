# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :ash_oban
end
