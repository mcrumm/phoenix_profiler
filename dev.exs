# iex -S mix dev
Logger.configure(level: :debug)

# Configure esbuild (the version is required)
Application.put_env(:esbuild, :version, "0.13.10")

Application.put_env(:esbuild, :default,
  args: ~w(js/app.js --bundle --target=es2016 --outdir=../static/assets),
  cd: Path.expand("dev/assets", __DIR__),
  env: %{"NODE_PATH" => Path.expand("deps", __DIR__)}
)

Application.ensure_all_started(:esbuild)

# Configures the endpoint
Application.put_env(:phoenix_profiler, DemoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Hu4qQN3iKzTV4fJxhorPQlA/osH9fAMtbtjVS58PFgfw3ja5Z18Q/WSNR9wP4OfW",
  live_view: [signing_salt: "hMegieSe"],
  http: [port: System.get_env("PORT") || 4000],
  debug_errors: true,
  check_origin: false,
  pubsub_server: Demo.PubSub,
  render_errors: [view: DemoWeb.ErrorView, accepts: ~w(html json), layout: false],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/phoenix_profiler/.*(ex)$",
      ~r"dev/demo_web/(live|views)/.*(ex)$",
      ~r"dev/demo_web/templates/.*(eex)$"
    ]
  ],
  phoenix_profiler: true
)

defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler

  plug PhoenixProfiler

  @session_options [
    store: :cookie,
    key: "_demo_key",
    signing_salt: "/VEDsdfsffMnp5"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [session: @session_options]
    ]

  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

  plug Plug.Static,
    at: "/",
    from: "dev/static",
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session, @session_options

  plug DemoWeb.Router
end

Application.put_env(:phoenix, :serve_endpoints, true)

Task.start(fn ->
  children = [
    {Phoenix.PubSub, [name: Demo.PubSub, adapter: Phoenix.PubSub.PG2]},
    DemoWeb.Endpoint
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  Process.sleep(:infinity)
end)
