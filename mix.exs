defmodule PhoenixProfiler.MixProject do
  use Mix.Project

  @version "0.1.0"
  @phoenix_version_requirement ">= 1.5.3"

  def project do
    [
      app: :phoenix_profiler,
      version: @version,
      elixir: "~> 1.8",
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
    phoenix() ++
      [
        {:phoenix_live_view, "~> 0.17.0 or ~> 0.16.0 or ~> 0.15.0 or ~> 0.14.3"},
        {:phoenix_live_dashboard, "~> 0.6.0 or ~> 0.5.0 or ~> 0.4.0 or ~> 0.3.0", optional: true},
        # Dev Dependencies
        {:phoenix_live_reload, "~> 1.3", only: :dev},
        {:plug_cowboy, "~> 2.0", only: :dev},
        {:jason, "~> 1.0", only: [:dev, :test, :docs]},
        {:ex_doc, "~> 0.25", only: :docs},
        {:esbuild, "~> 0.2", runtime: false, only: :dev},
        {:floki, ">= 0.26.0", only: :test}
      ]
  end

  defp phoenix do
    if vsn = System.get_env("PHOENIX_PROFILER_PHOENIX_VERSION") do
      phoenix(vsn)
    else
      []
    end
  end

  defp phoenix(vsn) do
    if Version.match?(vsn, @phoenix_version_requirement) do
      [{:phoenix, "#{vsn}"}]
    else
      []
    end
  rescue
    _ ->
      raise ArgumentError, """
      PhoenixProfiler expected a valid Phoenix version, got: #{inspect(vsn)}

      To override the version of Phoenix installed while developing PhoenixProfiler,
      export a system environment variable named PHOENIX_PROFILER_PHOENIX_VERSION.

      For example, if you want to install Phoenix v1.6.6, do the following:

      $ export PHOENIX_PROFILER_PHOENIX_VERSION=1.6.6

      """
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
      links: %{
        "GitHub" => "https://github.com/mcrumm/phoenix_profiler",
        "Sponsor" => "https://github.com/sponsors/mcrumm"
      },
      files: ~w(lib priv CHANGELOG.md LICENSE mix.exs README.md)
    ]
  end
end
