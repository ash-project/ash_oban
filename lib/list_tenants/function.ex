# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ListTenants.Function do
  @moduledoc false

  @behaviour AshOban.ListTenants

  @impl true
  def list_tenants([{:fun, {m, f, a}}]) do
    apply(m, f, a)
  end

  @impl true
  def list_tenants([{:fun, fun}]) do
    fun.()
  end
end
