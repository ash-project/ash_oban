defmodule AshOban.ActorPersister do
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
