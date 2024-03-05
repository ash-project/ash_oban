defmodule AshOban.MixProject do
  use Mix.Project

  @version "0.2.2"

  @description """
  An Ash.Resource extension for integrating with Oban.
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
      dialyzer: [plt_add_apps: [:ash]],
      docs: docs(),
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
      name: :ash_oban,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation),
      links: %{
        GitHub: "https://github.com/ash-project/ash_oban"
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
      main: "get-started-with-ash-oban",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extra_section: "GUIDES",
      extras: [
        "documentation/tutorials/get-started-with-ash-oban.md",
        "documentation/dsls/DSL:-AshOban.md"
      ],
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        "How To": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        DSLs: ~r'documentation/dsls'
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
        {:ash, "~> 2.9 and >= 2.9.27"},
        {:spark, ">= 1.1.3"},
        {:oban, "~> 2.15"},
        {:ex_doc, "~> 0.22", only: [:dev, :test], runtime: false},
        {:ex_check, "~> 0.12", only: [:dev, :test]},
        {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
        {:git_ops, "~> 2.5", only: [:dev, :test]},
        {:excoveralls, "~> 0.13", only: [:dev, :test]},
        {:postgrex, "~> 0.17.4"}
      ]
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links",
        "spark.cheat_sheets_in_search"
      ],
      "spark.formatter": "spark.formatter --extensions AshOban",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshOban",
      "spark.cheat_sheets_in_search": "spark.cheat_sheets_in_search --extensions AshOban",
      "ecto.gen.migration": "ecto.gen.migration --migrations-path=test_migrations",
      "ecto.migrate": "ecto.migrate --migrations-path=test_migrations",
      "ecto.setup": ["ecto.create", "ecto.migrate"]
    ]
  end
end
