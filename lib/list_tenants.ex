# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ListTenants do
  @moduledoc """
  The behaviour for listing tenants.
  """
  @callback list_tenants(opts :: Keyword.t()) :: [term()]
end
