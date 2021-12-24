Application.put_env(:phoenix_profiler, PhoenixProfilerTest.Endpoint,
  url: [host: "localhost", port: 4000],
  secret_key_base: "LIyk9co9Mt8KowH/g1WeMkufq/9Bz1XuEZMhCZAwnBc7VFKCfkDq/vRw+Xso4Q0q",
  live_view: [signing_salt: "NbA2FdHo"],
  render_errors: [view: PhoenixProfilerTest.ErrorView],
  check_origin: false,
  pubsub_server: PhoenixProfilerTest.PubSub,
  phoenix_profiler: [server: PhoenixProfilerTest.Profiler]
)

Application.put_env(:phoenix_profiler, PhoenixProfilerTest.EndpointDisabled,
  url: [host: "localhost", port: 4000],
  secret_key_base: "LIyk9co9Mt8KowH/g1WeMkufq/9Bz1XuEZMhCZAwnBc7VFKCfkDq/vRw+Xso4Q0q",
  live_view: [signing_salt: "NbA2FdHo"],
  render_errors: [view: PhoenixProfilerTest.ErrorView],
  check_origin: false,
  pubsub_server: PhoenixProfilerTest.PubSub,
  phoenix_profiler: false
)

defmodule PhoenixProfilerTest.Profiler do
  use PhoenixProfiler, otp_app: :phoenix_profiler
end

defmodule PhoenixProfilerTest.ErrorView do
  use Phoenix.View, root: "test/templates"

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule PhoenixProfilerTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :fetch_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PhoenixProfilerTest do
    pipe_through :browser

    get "/", PageController, :index
    get "/disabled", PageController, :disabled

    forward "/plug-router", PlugRouter
  end

  scope "/api", PhoenixProfilerTest do
    pipe_through :api

    get "/", APIController, :index
  end
end

defmodule PhoenixProfilerTest.PlugRouter do
  use Plug.Router
  import Phoenix.Controller

  plug :match
  plug :dispatch

  get "/" do
    html(conn, "<html><body>Home</body></html>")
  end

  match _ do
    html(conn, "<html><body>Not Found</body></html>")
  end
end

defmodule PhoenixProfilerTest.PageController do
  use Phoenix.Controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<html><body><p>Hello, world</p></body></html>")
  end

  def disabled(conn, _params) do
    conn
    |> PhoenixProfiler.disable()
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<html><body><p>The profiler should be disabled.</p></body></html>")
  end
end

defmodule PhoenixProfilerTest.APIController do
  use Phoenix.Controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"hello" => "world"}))
  end
end

defmodule PhoenixProfilerTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler

  plug PhoenixProfiler
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug PhoenixProfilerTest.Router
end

defmodule PhoenixProfilerTest.EndpointDisabled do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler
end

Supervisor.start_link(
  [
    PhoenixProfilerTest.Profiler,
    {Phoenix.PubSub, name: PhoenixProfilerTest.PubSub, adapter: Phoenix.PubSub.PG2},
    PhoenixProfilerTest.Endpoint,
    PhoenixProfilerTest.EndpointDisabled
  ],
  strategy: :one_for_one
)

ExUnit.start()
