# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.MixProject do
  use Mix.Project

  @version "0.5.1"

  @description """
  The extension for integrating Ash resources with Oban.
  """

  def project do
    [
      app: :ash_oban,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      package: package(),
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [plt_add_apps: [:ash, :mix]],
      consolidate_protocols: Mix.env() == :prod,
      docs: &docs/0,
      description: @description,
      source_url: "https://github.com/ash-project/ash_oban",
      homepage_url: "https://github.com/ash-project/ash_oban"
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.gen.migration": :test,
        "test.migrate": :test,
        "test.create": :test
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "Zach Daniel <zach@zachdaniel.dev>"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* usage-rules.md
      CHANGELOG* documentation),
      links: %{
        "GitHub" => "https://github.com/ash-project/ash_oban",
        "Changelog" => "https://github.com/ash-project/ash_oban/blob/main/CHANGELOG.md",
        "Discord" => "https://discord.gg/HTHRaaVPUc",
        "Website" => "https://ash-hq.org",
        "Forum" => "https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum",
        "REUSE Compliance" => "https://api.reuse.software/info/github.com/ash-project/ash_oban"
      }
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extra_section: "GUIDES",
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/getting-started-with-ash-oban.md",
        "documentation/topics/triggers-and-scheduled-actions.md",
        {"documentation/dsls/DSL-AshOban.md", search_data: Spark.Docs.search_data_for(AshOban)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        "How To": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        DSLs: ~r'documentation/dsls',
        "About AshOban": [
          "CHANGELOG.md"
        ]
      ],
      groups_for_modules: [
        AshOban: [
          AshOban
        ],
        Utilities: [
          AshOban.Changes.BuiltinChanges,
          AshOban.Changes.RunObanTrigger
        ],
        Authorization: [
          AshOban.Checks.AshObanInteraction
        ],
        Introspection: [
          AshOban.Info,
          AshOban.Trigger,
          AshOban.Schedule
        ],
        Testing: [
          AshOban.Test
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    oban_dep =
      if System.get_env("ASH_OBAN_CI_OBAN_PRO") == "false" do
        []
      else
        # We can't currently use this as we don't have a license for oban_pro that we can use
        # [{:oban_pro, "~> 1.0", repo: "oban", only: [:dev,]}]
        []
      end

    oban_dep ++
      [
        {:ash, github: "ash-project/ash", override: true},
        {:oban, "~> 2.15"},
        {:postgrex, "~> 0.18"},
        # dev/test dependencies
        {:igniter, "~> 0.6.1", only: [:dev, :test]},
        {:simple_sat, "~> 0.1", only: [:dev, :test]},
        {:ex_doc, "~> 0.37-rc", only: [:dev, :test], runtime: false},
        {:ex_check, "~> 0.12", only: [:dev, :test]},
        {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:git_ops, "~> 2.5", only: [:dev, :test]},
        {:excoveralls, "~> 0.13", only: [:dev, :test]},
        {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false}
      ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash"]
      "main" -> [git: "https://github.com/ash-project/ash.git"]
      version -> "~> #{version}"
    end
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "test.migrate": ["ecto.migrate"],
      "test.create": ["ecto.create"],
      "spark.formatter": "spark.formatter --extensions AshOban",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshOban",
      "ecto.gen.migration": "ecto.gen.migration --migrations-path=test_migrations",
      "ecto.migrate": "ecto.migrate --migrations-path=test_migrations",
      "ecto.setup": ["ecto.create", "ecto.migrate"]
    ]
  end
end
