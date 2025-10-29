# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Verifiers.VerifyUseTenantFromRecord do
  @moduledoc """
  Verifies that when `use_tenant_from_record?` is set to true, the multitenancy
  `parse_attribute` and `tenant_from_attribute` options are either both at their
  defaults or both customized.
  """
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> AshOban.Info.oban_triggers()
    |> Enum.filter(fn trigger -> trigger.use_tenant_from_record? end)
    |> Enum.each(fn trigger ->
      parse_attribute = Ash.Resource.Info.multitenancy_parse_attribute(module)
      tenant_from_attribute = Ash.Resource.Info.multitenancy_tenant_from_attribute(module)

      # Check if parse_attribute is at default
      parse_at_default? = is_identity_mfa?(parse_attribute)

      # Check if tenant_from_attribute is at default
      tenant_from_at_default? = is_identity_mfa?(tenant_from_attribute)

      # Both should be at default OR both should be customized
      unless parse_at_default? == tenant_from_at_default? do
        raise Spark.Error.DslError,
          module: module,
          path: [:oban, :triggers, trigger.name],
          message: """
          When `use_tenant_from_record?` is true, the multitenancy options
          `parse_attribute` and `tenant_from_attribute` must either both be
          at their default values or both be customized.

          Currently:
          - parse_attribute: #{inspect(parse_attribute)} #{if parse_at_default?, do: "(default)", else: "(customized)"}
          - tenant_from_attribute: #{inspect(tenant_from_attribute)} #{if tenant_from_at_default?, do: "(default)", else: "(customized)"}

          These options are inverses of each other, so if you customize one,
          you must customize the other to maintain consistency.
          """
      end
    end)

    :ok
  end

  # Check if an MFA tuple represents the identity function (the default)
  defp is_identity_mfa?({mod, fun, []}) when fun in [:identity, :_identity] do
    # The default MFAs use :identity or :_identity function names
    # Check if it's likely a default by looking at the function name
    function_exported?(mod, fun, 1)
  end

  defp is_identity_mfa?(_), do: false
end
