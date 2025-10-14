# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ActorPersister do
  @moduledoc """
  A behaviour for storing and retrieving an actor from oban job arguments
  """
  @type actor_json :: any
  @type actor :: any

  @callback store(actor :: actor) :: actor_json :: actor_json
  @callback lookup(actor_json :: actor_json | nil) :: {:ok, actor | nil} | {:error, Ash.Error.t()}

  defmacro __using__(_) do
    quote do
      @behaviour AshOban.ActorPersister
    end
  end
end
