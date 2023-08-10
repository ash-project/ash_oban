defmodule CronFlagTest do
  use ExUnit.Case
  doctest AshOban

  defmodule Api do
    use Ash.Api, validate_config_inclusion?: false

    resources do
      registry CronFlagTest.Registry
    end
  end

  defmodule Registry do
    use Ash.Registry

    entries do
      entry CronFlagTest.DefaultTrigger
      entry CronFlagTest.CronTrigger
      entry CronFlagTest.NonCronTrigger
    end
  end

  defmodule DefaultTrigger do
    use Ash.Resource,
      validate_api_inclusion?: false,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        api Api

        trigger :process do
          action :process
          where expr(processed != true)
          worker_read_action(:read)
        end
      end
    end

    actions do
      defaults [:create]

      read :read do
        primary? true
        pagination keyset?: true
      end

      update :process do
        change set_attribute(:processed, true)
      end
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule CronTrigger do
    use Ash.Resource,
      validate_api_inclusion?: false,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        api Api

        trigger :process do
          action :process
          where expr(processed != true)
          worker_read_action(:read)
          cron? true
        end
      end
    end

    actions do
      defaults [:create]

      read :read do
        primary? true
        pagination keyset?: true
      end

      update :process do
        change set_attribute(:processed, true)
      end
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule NonCronTrigger do
    use Ash.Resource,
      validate_api_inclusion?: false,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshOban]

    oban do
      triggers do
        api Api

        trigger :process do
          action :process
          where expr(processed != true)
          worker_read_action(:read)
          cron? false
        end
      end
    end

    actions do
      defaults [:create]

      read :read do
        primary? true
        pagination keyset?: true
      end

      update :process do
        change set_attribute(:processed, true)
      end
    end

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
    end
  end

  describe "Cron? flag" do
    test "defaults to true if not provided" do
      assert [%AshOban.Trigger{cron?: true}] = AshOban.Info.oban_triggers(DefaultTrigger)
    end

    test "is correctly set from DSL when provided" do
      assert [%AshOban.Trigger{cron?: true}] = AshOban.Info.oban_triggers(CronTrigger)
      assert [%AshOban.Trigger{cron?: false}] = AshOban.Info.oban_triggers(NonCronTrigger)
    end

    test "does not create scheduler module if set to false" do
      refute Code.ensure_loaded?(NonCronTrigger.AshOban.Scheduler.Process)
    end

    test "creates scheduler module if not provided" do
      assert Code.ensure_loaded?(DefaultTrigger.AshOban.Scheduler.Process)
    end

    test "creates scheduler module if set to true" do
      assert Code.ensure_loaded?(CronTrigger.AshOban.Scheduler.Process)
    end

    test "does not configure a cron worker for trigger with cron? flag set to false" do
      config =
        AshOban.config([CronFlagTest.Api],
          plugins: [
            {Oban.Plugins.Cron, crontab: []}
          ],
          queues: [
            default_trigger_process: 1,
            cron_trigger_process: 1,
            non_cron_trigger_process: 1
          ]
        )

      plugins = config[:plugins]
      cron = plugins[Oban.Plugins.Cron]
      cron_tab = cron[:crontab]

      refute Enum.any?(cron_tab, fn {_spec, module, _opts} ->
               module == NonCronTrigger.AshOban.Scheduler.Process
             end)
    end

    test "configures a cron worker for trigger with cron? flag set to true" do
      config =
        AshOban.config([CronFlagTest.Api],
          plugins: [
            {Oban.Plugins.Cron, crontab: []}
          ],
          queues: [
            default_trigger_process: 1,
            cron_trigger_process: 1,
            non_cron_trigger_process: 1
          ]
        )

      plugins = config[:plugins]
      cron = plugins[Oban.Plugins.Cron]
      cron_tab = cron[:crontab]

      assert Enum.any?(cron_tab, fn {_spec, module, _opts} ->
               module == CronTrigger.AshOban.Scheduler.Process
             end)
    end

    test "configures a cron worker for trigger with cron? flag not provided" do
      config =
        AshOban.config([CronFlagTest.Api],
          plugins: [
            {Oban.Plugins.Cron, crontab: []}
          ],
          queues: [
            default_trigger_process: 1,
            cron_trigger_process: 1,
            non_cron_trigger_process: 1
          ]
        )

      plugins = config[:plugins]
      cron = plugins[Oban.Plugins.Cron]
      cron_tab = cron[:crontab]

      assert Enum.any?(cron_tab, fn {_spec, module, _opts} ->
               module == DefaultTrigger.AshOban.Scheduler.Process
             end)
    end
  end
end
