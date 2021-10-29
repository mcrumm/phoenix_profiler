defmodule PhoenixProfiler.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :phoenix_profiler,
      version: @version,
      elixir: "~> 1.7",
      compilers: [:phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs(),
      homepage_url: "https://github.com/mcrumm/phoenix_profiler",
      description: "Phoenix Web Profiler & Debug Toolbar",
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixProfiler.Application, []}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      dev: "run --no-halt dev.exs"
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.4.7 or ~> 1.5.0 or ~> 1.6.0"},
      {:phoenix_live_view, "~> 0.14.3 or ~> 0.15.0 or ~> 0.16.0 or ~> 0.17.0"},
      {:phoenix_live_dashboard, "~> 0.3.0 or ~> 0.4.0 or ~> 0.5.0 or ~> 0.6.0", optional: true},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:plug_cowboy, "~> 2.0", only: :dev},
      {:jason, "~> 1.0", only: [:dev, :test, :docs]},
      {:ex_doc, "~> 0.25", only: :docs},
      {:esbuild, "~> 0.2", runtime: false},
      {:floki, ">= 0.26.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "PhoenixProfiler",
      source_ref: "v#{@version}",
      source_url: "https://github.com/mcrumm/phoenix_profiler"
    ]
  end

  defp package do
    [
      maintainers: ["Michael Allen Crumm Jr."],
      licenses: ["MIT"],
      links: %{github: "https://github.com/mcrumm/phoenix_profiler"},
      files: ~w(lib priv CHANGELOG.md LICENSE mix.exs README.md)
    ]
  end
end
