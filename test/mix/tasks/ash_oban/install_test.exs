# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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
       |[
       |  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
     - |  import_deps: [:oban]
     + |  import_deps: [:ash_oban, :oban]
       |]
       |
    """)
  end

  test "adds the cron plugin to the oban config", %{igniter: igniter} do
    igniter
    |> assert_has_patch("config/config.exs", ~S'''
      |import Config
      |
    + |config :ash_oban, pro?: false
    ''')
    |> assert_has_patch("config/config.exs", ~S'''
       |config :test, Oban,
       |  engine: Oban.Engines.Basic,
       |  notifier: Oban.Notifiers.Postgres,
       |  queues: [default: 10],
     - |  repo: Test.Repo
     + |  repo: Test.Repo,
     + |  plugins: [{Oban.Plugins.Cron, []}]
       |
       |import_config "#{config_env()}.exs"
    ...|
    ''')
  end

  test "adds AshOban.config to the Oban entry in the Application Supervision tree", %{
    igniter: igniter
  } do
    igniter
    |> assert_has_patch("lib/test/application.ex", """
    ...|
       |  @impl true
       |  def start(_type, _args) do
     - |    children = [{Oban, Application.fetch_env!(:test, Oban)}]
     + |    children = [
     + |      {Oban,
     + |       AshOban.config(
     + |         Application.fetch_env!(:test, :ash_domains),
     + |         Application.fetch_env!(:test, Oban)
     + |       )}
     + |    ]
       |
       |    opts = [strategy: :one_for_one, name: Test.Supervisor]
    ...|
    """)
  end
end
