# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

excluded =
  if Code.ensure_loaded?(Oban.Pro.Workers.Chunk) do
    []
  else
    [:oban_pro]
  end

{:ok, _} = AshOban.Test.Repo.start_link()

ExUnit.start(exclude: excluded)
