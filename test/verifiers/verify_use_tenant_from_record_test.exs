# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Verifiers.VerifyUseTenantFromRecordTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "no errors if both parse_attribute and tenant_from_attribute use defaults" do
    output =
      capture_io(:stderr, fn ->
        defmodule DefaultResource do
          @moduledoc false
          use Ash.Resource,
            domain: AshOban.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshOban]

          multitenancy do
            strategy(:attribute)
            attribute(:tenant_id)
          end

          oban do
            triggers do
              trigger :test_trigger do
                action :test_action
                use_tenant_from_record? true
                scheduler_cron false

                worker_module_name __MODULE__.Worker
              end
            end
          end

          actions do
            defaults([:read])

            update :test_action do
              accept([])
            end
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:tenant_id, :string, allow_nil?: false)
          end

          def custom_parse(tenant), do: tenant
        end
      end)

    assert output == ""
  end

  test "raises error when parse_attribute is customized but tenant_from_attribute is at default" do
    output =
      capture_io(:stderr, fn ->
        defmodule ParseCustomizedOnlyResource do
          @moduledoc false
          use Ash.Resource,
            domain: AshOban.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshOban]

          multitenancy do
            strategy(:attribute)
            attribute(:tenant_id)
            parse_attribute({__MODULE__, :custom_parse, []})
          end

          oban do
            triggers do
              trigger :test_trigger do
                action :test_action
                use_tenant_from_record? true
                scheduler_cron false

                worker_module_name __MODULE__.Worker
              end
            end
          end

          actions do
            defaults([:read])

            update :test_action do
              accept([])
            end
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:tenant_id, :string, allow_nil?: false)
          end

          def custom_parse(tenant), do: tenant
        end
      end)

    assert output =~ "When `use_tenant_from_record?` is true"
    assert output =~ ~r/parse_attribute:.*\(customized\)/
    assert output =~ ~r/tenant_from_attribute:.*\(default\)/
    assert output =~ "These options are inverses of each other"
  end

  test "raises error when tenant_from_attribute is customized but parse_attribute is at default" do
    output =
      capture_io(:stderr, fn ->
        defmodule TenantFromCustomizedOnlyResource do
          @moduledoc false
          use Ash.Resource,
            domain: AshOban.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshOban]

          multitenancy do
            strategy(:attribute)
            attribute(:tenant_id)
            tenant_from_attribute({__MODULE__, :custom_tenant_from, []})
          end

          oban do
            triggers do
              trigger :test_trigger do
                action :test_action
                use_tenant_from_record? true
                scheduler_cron false

                worker_module_name __MODULE__.Worker
              end
            end
          end

          actions do
            defaults([:read])

            update :test_action do
              accept([])
            end
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:tenant_id, :string, allow_nil?: false)
          end

          def custom_tenant_from(tenant), do: tenant
        end
      end)

    assert output =~ "When `use_tenant_from_record?` is true"
    assert output =~ ~r/parse_attribute:.*\(default\)/
    assert output =~ ~r/tenant_from_attribute:.*\(customized\)/
    assert output =~ "These options are inverses of each other"
  end

  test "no errors if both parse_attribute and tenant_from_attribute are customized" do
    output =
      capture_io(:stderr, fn ->
        defmodule BothCustomizedResource do
          @moduledoc false
          use Ash.Resource,
            domain: AshOban.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshOban]

          multitenancy do
            strategy(:attribute)
            attribute(:tenant_id)
            parse_attribute({__MODULE__, :custom_parse, []})
            tenant_from_attribute({__MODULE__, :custom_tenant_from, []})
          end

          oban do
            triggers do
              trigger :test_trigger do
                action :test_action
                use_tenant_from_record? true
                scheduler_cron false

                worker_module_name __MODULE__.Worker
              end
            end
          end

          actions do
            defaults([:read])

            update :test_action do
              accept([])
            end
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:tenant_id, :string, allow_nil?: false)
          end

          def custom_parse(tenant), do: tenant
          def custom_tenant_from(tenant), do: tenant
        end
      end)

    assert output == ""
  end

  test "no errors when use_tenant_from_record? is false regardless of configuration" do
    output =
      capture_io(:stderr, fn ->
        defmodule UseTenantFromRecordFalseResource do
          @moduledoc false
          use Ash.Resource,
            domain: AshOban.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshOban]

          multitenancy do
            strategy(:attribute)
            attribute(:tenant_id)
            parse_attribute({__MODULE__, :custom_parse, []})
            # tenant_from_attribute left at default
          end

          oban do
            triggers do
              trigger :test_trigger do
                action :test_action
                use_tenant_from_record? false
                scheduler_cron false

                worker_module_name AshOban.Verifiers.VerifyUseTenantFromRecordTest.UseTenantFromRecordFalseResource.Worker
              end
            end
          end

          actions do
            defaults([:read])

            update :test_action do
              accept([])
            end
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:tenant_id, :string, allow_nil?: false)
          end

          def custom_parse(tenant), do: tenant
        end
      end)

    assert output == ""
  end
end
