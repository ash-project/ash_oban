defmodule Mix.Tasks.AshOban.InstallTest do
  use ExUnit.Case

  import Igniter.Test

  setup_all do
    repo = """
    defmodule Test.Repo do
      @moduledoc false

      use Ecto.Repo, otp_app: :test, adapter: Ecto.Adapters.Postgres
    end
    """

    files = %{"lib/test/repo.ex" => repo}

    igniter =
      [files: files]
      |> test_project()
      |> Igniter.compose_task("oban.install")
      |> apply_igniter!()
      |> Igniter.compose_task("ash_oban.install")

    [igniter: igniter]
  end

  test "adds ash_oban to the formatter", %{igniter: igniter} do
    igniter
    |> assert_has_patch(".formatter.exs", """
       ...|
    2 2   |[
    3 3   |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
    4   - |  import_deps: [:oban]
      4 + |  import_deps: [:ash_oban, :oban]
    5 5   |]
    6 6   |
    """)
  end

  test "adds the cron plugin to the oban config", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/config.exs", ~S'''
    1  1   |import Config
    2  2   |
       3 + |config :ash_oban, pro?: false
       4 + |
    3  5   |config :test, Oban,
    4  6   |  engine: Oban.Engines.Basic,
    5  7   |  notifier: Oban.Notifiers.Postgres,
    6  8   |  queues: [default: 10],
    7    - |  repo: Test.Repo
       9 + |  repo: Test.Repo,
      10 + |  plugins: [{Oban.Pro.Plugins.DynamicCron, []}]
    8 11   |
    9 12   |import_config "#{config_env()}.exs"
        ...|
    ''')
  end

  test "adds AshOban.config to the Oban entry in the Application Supervision tree", %{
    igniter: igniter
  } do
    igniter
    |> assert_has_patch("lib/test/application.ex", """
         ...|
     6  6   |  @impl true
     7  7   |  def start(_type, _args) do
     8    - |    children = [{Oban, Application.fetch_env!(:test, Oban)}]
        8 + |    children = [
        9 + |      {Oban,
       10 + |       AshOban.config(
       11 + |         Application.fetch_env!(:test, :ash_domains),
       12 + |         Application.fetch_env!(:test, Oban)
       13 + |       )}
       14 + |    ]
     9 15   |
    10 16   |    opts = [strategy: :one_for_one, name: Test.Supervisor]
         ...|
    """)
  end
end
