# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Repo.Migrations.CreateTriggerWhereTickets do
  use Ecto.Migration

  def change do
    create table(:trigger_where_tickets, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :state, :text, null: false
    end
  end
end
