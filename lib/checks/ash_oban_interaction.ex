# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Checks.AshObanInteraction do
  @moduledoc """
  This check is true if the context `private.ash_oban?` is set to true.

  This context will only ever be set in code that is called internally by
  `ash_oban`, allowing you to create a bypass in your policies on your
  user/user_token resources.

  ```elixir
  policies do
    bypass AshObanInteraction do
      authorize_if always()
    end
  end
  ```
  """
  use Ash.Policy.SimpleCheck

  @impl Ash.Policy.Check
  def describe(_) do
    "AshOban is performing this interaction"
  end

  @impl Ash.Policy.SimpleCheck
  def match?(_, %{subject: %{context: %{private: %{ash_oban?: true}}}}, _), do: true
  def match?(_, _, _), do: false
end
