import Config

config :spark, :formatter,
  remove_parens?: true,
  "Ash.Domain": [],
  "Ash.Registry": [],
  "Ash.Resource": []

config :ash_oban, test: true

config :ash_oban, ecto_repos: [AshOban.Test.Repo]
config :logger, level: :warning

if Mix.env() == :test do
  config :ash_oban, :oban,
    testing: :manual,
    repo: AshOban.Test.Repo,
    prefix: "private",
    plugins: [
      {Oban.Plugins.Cron, []}
    ],
    queues: [
      triggered_process: 10,
      triggered_process_2: 10,
      triggered_say_hello: 10
    ]

  config :ash_oban, actor_persister: AshOban.Test.ActorPersister

  # sobelow_skip ["Config.Secrets"]
  config :ash_oban, AshOban.Test.Repo,
    username: "postgres",
    password: "postgres",
    database: "ash_oban_test",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox

  config :ash, :validate_domain_resource_inclusion?, false
end

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshOban.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/ash-project/ash_oban",
    # Instructs the tool to manage your mix version in your `mix.exs` file
    # See below for more information
    manage_mix_version?: true,
    # Instructs the tool to manage the version in your README.md
    # Pass in `true` to use `"README.md"` or a string to customize
    manage_readme_version: [
      "README.md",
      "documentation/tutorials/get-started-with-ash-oban.md"
    ],
    version_tag_prefix: "v"
end
