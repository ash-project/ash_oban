import Config

config :spark, :formatter,
  remove_parens?: true,
  "Ash.Api": [],
  "Ash.Registry": [],
  "Ash.Resource": []

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
