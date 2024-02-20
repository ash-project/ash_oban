defmodule AshOban.Test.ActorPersister do
  @moduledoc false
  use AshOban.ActorPersister

  defmodule FakeActor do
    @moduledoc false
    defstruct id: nil
  end

  def store(%FakeActor{id: id}) do
    %{"id" => id}
  end

  def lookup(%{"id" => id}) do
    {:ok, %FakeActor{id: id}}
  end

  def lookup(nil), do: {:ok, nil}
end
