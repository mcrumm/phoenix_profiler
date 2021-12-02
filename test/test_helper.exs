Application.put_env(:phoenix_web_profiler, PhoenixWeb.ProfilerTest.Endpoint,
  url: [host: "localhost", port: 4000],
  secret_key_base: "LIyk9co9Mt8KowH/g1WeMkufq/9Bz1XuEZMhCZAwnBc7VFKCfkDq/vRw+Xso4Q0q",
  live_view: [signing_salt: "NbA2FdHo"],
  render_errors: [view: PhoenixWeb.ProfilerTest.ErrorView],
  check_origin: false,
  pubsub_server: PhoenixWeb.ProfilerTest.PubSub,
  phoenix_web_profiler: true
)

Application.put_env(:phoenix_web_profiler, PhoenixWeb.ProfilerTest.EndpointDisabled,
  url: [host: "localhost", port: 4000],
  secret_key_base: "LIyk9co9Mt8KowH/g1WeMkufq/9Bz1XuEZMhCZAwnBc7VFKCfkDq/vRw+Xso4Q0q",
  live_view: [signing_salt: "NbA2FdHo"],
  render_errors: [view: PhoenixWeb.ProfilerTest.ErrorView],
  check_origin: false,
  pubsub_server: PhoenixWeb.ProfilerTest.PubSub,
  phoenix_web_profiler: false
)

defmodule PhoenixWeb.ProfilerTest.ErrorView do
  use Phoenix.View, root: "test/templates"

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule PhoenixWeb.ProfilerTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :fetch_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PhoenixWeb.ProfilerTest do
    pipe_through :browser

    get "/", PageController, :index

    forward "/plug-router", PlugRouter
  end

  scope "/api", PhoenixWeb.ProfilerTest do
    pipe_through :api

    get "/", APIController, :index
  end
end

defmodule PhoenixWeb.ProfilerTest.PlugRouter do
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

defmodule PhoenixWeb.ProfilerTest.PageController do
  use Phoenix.Controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, "<html><body><p>Hello, world</p></body></html>")
  end
end

defmodule PhoenixWeb.ProfilerTest.APIController do
  use Phoenix.Controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"hello" => "world"}))
  end
end

defmodule PhoenixWeb.ProfilerTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_web_profiler

  plug PhoenixWeb.Profiler
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug PhoenixWeb.ProfilerTest.Router
end

defmodule PhoenixWeb.ProfilerTest.EndpointDisabled do
  use Phoenix.Endpoint, otp_app: :phoenix_web_profiler
end

Supervisor.start_link(
  [
    {Phoenix.PubSub, name: PhoenixWeb.ProfilerTest.PubSub, adapter: Phoenix.PubSub.PG2},
    PhoenixWeb.ProfilerTest.Endpoint,
    PhoenixWeb.ProfilerTest.EndpointDisabled
  ],
  strategy: :one_for_one
)

ExUnit.start()
