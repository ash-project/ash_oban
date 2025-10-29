# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Verifiers.VerifyUseTenantFromRecordTest do
  use ExUnit.Case, async: true

  test "no warnings if both parse_attribute and tenant_from_attribute use defaults" do
    log =
      ExUnit.CaptureIO.capture_io(fn ->
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

    refute log == "warning"
  end

  test "warns when parse_attribute is customized but tenant_from_attribute is at default" do
    log =
      ExUnit.CaptureIO.capture_io(fn ->
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

    assert log =~ "When `use_tenant_from_record?` is true"

    assert log =~
             "parse_attribute: {AshOban.Verifiers.VerifyUseTenantFromRecordTest.ParseCustomizedOnlyResource, :custom_parse, []} (customized)"

    assert log =~ "tenant_from_attribute: {Ash.Resource.Dsl, :identity, []} (default)"
    assert log =~ "These options are inverses of each other"
  end

  test "warns when tenant_from_attribute is customized but parse_attribute is at default" do
    log =
      ExUnit.CaptureIO.capture_io(fn ->
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

    assert log =~ "When `use_tenant_from_record?` is true"
    assert log =~ "parse_attribute: {Ash.Resource.Dsl, :identity, []} (default)"

    assert log =~
             "tenant_from_attribute: {AshOban.Verifiers.VerifyUseTenantFromRecordTest.TenantFromCustomizedOnlyResource, :custom_tenant_from, []} (customized)"

    assert log =~ "These options are inverses of each other"
  end

  test "no warnings if both parse_attribute and tenant_from_attribute are customized" do
    log =
      ExUnit.CaptureIO.capture_io(fn ->
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

    refute log =~ "warning"
  end

  test "no warnings when use_tenant_from_record? is false regardless of configuration" do
    log =
      ExUnit.CaptureIO.capture_io(fn ->
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

    refute log =~ "warning"
  end
end
