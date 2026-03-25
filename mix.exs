defmodule Entrace.MixProject do
  use Mix.Project

  def project do
    [
      app: :entrace,
      version: "0.2.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Entrace",
      description: "Easy tracing on the BEAM with Elixir",
      source_url: "https://github.com/underjord/entrace",
      docs: [
        # The main page in the docs
        main: "readme",
        extras: ["README.md"]
      ],
      package: [
        name: :entrace,
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/underjord/entrace"}
      ],
      dialyzer: dialyzer()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Entrace.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  def package do
    [
      name: :entrace,
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/underjord/entrace"}
    ]
  end

  def aliases do
    [
      check: [
        "hex.audit",
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "credo",
        "deps.unlock --check-unused",
        "spellweaver.check",
        "dialyzer"
      ]
    ]
  end

  def dialyzer do
    [
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "extras"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:nstandard, "~> 0.2"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:ex2ms, "~> 1.7"},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:spellweaver, "~> 0.1", only: [:dev, :test], runtime: false}
    ]
  end
end
