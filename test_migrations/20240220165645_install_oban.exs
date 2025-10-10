# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Repo.Migrations.InstallOban do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(prefix: "private")
  end

  def down do
    Oban.Migrations.down(prefix: "private")
  end
end
