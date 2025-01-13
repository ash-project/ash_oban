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
