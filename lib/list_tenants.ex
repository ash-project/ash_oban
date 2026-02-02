# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ListTenants do
  @moduledoc """
  The behaviour for listing tenants.
  """
  @callback list_tenants(opts :: Keyword.t()) :: [term()]
end
