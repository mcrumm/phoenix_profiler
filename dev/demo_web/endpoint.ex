defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_web_profiler

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

  plug PhoenixWeb.Profiler

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Session, @session_options

  plug DemoWeb.Router
end
