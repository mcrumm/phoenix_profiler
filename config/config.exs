use Mix.Config

config :phoenix, :json_library, Jason

config :logger, level: :warn
config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.21",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../static/assets),
    cd: Path.expand("../dev/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
