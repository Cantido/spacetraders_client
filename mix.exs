defmodule SpacetradersClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :spacetraders_client,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {SpacetradersClient.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:phoenix_live_view, "~> 1.0"},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:faker, "~> 0.19.0-alpha.1", only: :test},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons, "~> 0.5.5"},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:ex_cldr, "~> 2.37"},
      {:ex_cldr_dates_times, "~> 2.20"},
      {:ex_cldr_numbers, "~> 2.33"},
      {:timex, "~> 3.7.11"},
      {:taido, path: "../taido"},
      {:motocho, path: "../motocho"},
      {:tesla, "~> 1.12"},
      {:hammer, "~> 6.2"},
      {:nebulex, "~> 2.6"},
      {:decorator, "~> 1.4"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:uniq, "~> 0.6.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.reset": ["ecto.drop", "ecto.create", "ecto.migrate"],
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind spacetraders_client", "esbuild spacetraders_client"],
      "assets.deploy": [
        "tailwind spacetraders_client --minify",
        "esbuild spacetraders_client --minify",
        "phx.digest"
      ]
    ]
  end
end
