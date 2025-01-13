defmodule AshOban.ListTenants do
  @moduledoc """
  The behaviour for listing tenants.
  """
  @callback list_tenants(opts :: Keyword.t()) :: [term()]
end
