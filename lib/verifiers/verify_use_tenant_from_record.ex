# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
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
    |> Enum.reduce_while(:ok, fn trigger, acc ->
      parse_attribute = Ash.Resource.Info.multitenancy_parse_attribute(module)
      tenant_from_attribute = Ash.Resource.Info.multitenancy_tenant_from_attribute(module)

      parse_at_default? = identity_mfa?(parse_attribute)
      tenant_from_at_default? = identity_mfa?(tenant_from_attribute)

      if parse_at_default? != tenant_from_at_default? do
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
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
          )}}
      else
        {:cont, acc}
      end
    end)
  end

  defp identity_mfa?({Ash.Resource.Dsl, :identity, []}), do: true
  defp identity_mfa?(_), do: false
end
