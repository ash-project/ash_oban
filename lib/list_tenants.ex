defmodule AshOban.ListTenants do
  @callback list_tenants(opts :: Keyword.t()) :: [term()]
end
