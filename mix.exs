defmodule PhoenixWeb.Debug.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :phoenix_web_debug,
      version: @version,
      elixir: "~> 1.12",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixWeb.Debug.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_live_view, "~> 0.14"},
      {:jason, "~> 1.0", only: [:dev, :test, :docs]},
      {:ex_doc, "~> 0.25", only: :docs}
    ]
  end

  defp docs do
    [
      main: "PhoenixWeb.Debug",
      source_ref: "v#{@version}",
      source_url: "https://github.com/mcrumm/phoenix_web_debug"
    ]
  end

  defp package do
    [
      maintainers: ["Michael Allen Crumm Jr."],
      licenses: ["MIT"],
      links: %{github: "https://github.com/mcrumm/phoenix_web_debug"},
      files: ~w(lib priv CHANGELOG.md LICENSE mix.exs README.md)
    ]
  end
end
