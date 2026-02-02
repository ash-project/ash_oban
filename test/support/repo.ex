# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :ash_oban
end
