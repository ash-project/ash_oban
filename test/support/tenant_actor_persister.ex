# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.TenantActorPersister do
  @moduledoc false
  # Resolves a stored actor only while it belongs to the tenant the job runs in, and tells the
  # calling process what it was asked.
  use AshOban.ActorPersister

  alias AshOban.Test.ActorPersister.FakeActor

  @memberships %{"member" => [1, 2], "zach" => ["acme"]}

  def store(%FakeActor{id: id}), do: %{"id" => id}

  def lookup(actor_json, context) do
    send(self(), {:lookup, actor_json, context})

    case actor_json do
      nil ->
        {:ok, nil}

      %{"id" => id} ->
        if context.tenant in Map.get(@memberships, id, []) do
          {:ok, %FakeActor{id: id}}
        else
          {:error, AshOban.Errors.CancelJob.exception(reason: :actor_not_in_tenant)}
        end
    end
  end
end
