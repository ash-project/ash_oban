# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Signals.Upgrader do
  @moduledoc """
  A behaviour for upgrading signals stored in jobs by an older version of the signal.

  Jobs store each signal as a map with string keys. Before a job runs, the map is passed to the
  signal's upgrader, if it has one, and then loaded with the signal's current definition. Fields
  the signal no longer has are ignored, and a required field that is missing fails the job, so an
  upgrader is only needed when a change would make stored signals invalid, like renaming a field
  or making one required.

  An upgrader can't tell which version wrote a map, so it looks at the map itself:

  ```elixir
  defmodule MyApp.Shop.Signals.Upgraders.OrderPlaced do
    use AshOban.Signals.Upgrader

    @impl true
    def upgrade(%{"customer_id" => customer_id} = signal, _opts) do
      {:ok, signal |> Map.delete("customer_id") |> Map.put("buyer_id", customer_id)}
    end

    def upgrade(signal, _opts), do: {:ok, signal}
  end
  ```
  """

  @callback upgrade(signal :: map(), opts :: Keyword.t()) :: {:ok, map()} | {:error, term()}

  defmacro __using__(_) do
    quote do
      @behaviour AshOban.Signals.Upgrader
    end
  end
end
