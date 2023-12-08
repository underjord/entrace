defmodule Entrace.MixProject do
  use Mix.Project

  def project do
    [
      app: :entrace,
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
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # {:ex2ms, "~> 1.6"}
      {:ex2ms, github: "lawik/ex2ms", ref: "actions-current-stacktrace-caller-line"}
    ]
  end

  defp aliases do
    []
  end
end
