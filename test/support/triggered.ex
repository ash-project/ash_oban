defmodule AshOban.Test.Triggered do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshOban]

  oban do
    api AshOban.Test.Api

    triggers do
      trigger :process do
        action :process
        where expr(processed != true)
        worker_read_action(:read)
      end

      trigger :process_2 do
        action :process
        where expr(processed != true)
        worker_read_action(:read)
        scheduler_cron false
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
