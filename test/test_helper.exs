Code.require_file("support/endpoint_helper.exs", __DIR__)

alias PhoenixProfiler.Integration.EndpointHelper

Application.put_env(:phoenix_profiler, PhoenixProfilerTest.Endpoint,
  url: [host: "localhost", port: 4000],
  secret_key_base: EndpointHelper.gen_secret_key(),
  live_view: [signing_salt: EndpointHelper.gen_salt()],
  check_origin: false,
  pubsub_server: PhoenixProfilerTest.PubSub,
  phoenix_profiler: [server: PhoenixProfilerTest.Profiler]
)

Application.put_env(:phoenix_profiler, PhoenixProfilerTest.EndpointDisabled,
  url: [host: "localhost", port: 4000],
  secret_key_base: EndpointHelper.gen_secret_key(),
  live_view: [signing_salt: EndpointHelper.gen_salt()],
  check_origin: false,
  pubsub_server: PhoenixProfilerTest.PubSub,
  phoenix_profiler: [server: PhoenixProfilerTest.Profiler, enable: false]
)

Application.put_env(:phoenix_profiler, PhoenixProfilerTest.EndpointNotConfigured,
  url: [host: "localhost", port: 4000],
  secret_key_base: EndpointHelper.gen_secret_key(),
  live_view: [signing_salt: EndpointHelper.gen_salt()],
  check_origin: false,
  pubsub_server: PhoenixProfilerTest.PubSub
)

defmodule PhoenixProfiler.ErrorView do
  def render(template, %{conn: conn}) do
    unless conn.private.phoenix_endpoint do
      raise "no endpoint in error view"
    end

    err = "#{template} from PhoenixProfiler.ErrorView"

    if String.ends_with?(template, ".html") do
      Phoenix.HTML.html_escape("<html><body>#{err}</body></html>")
    else
      err
    end
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
  use PhoenixProfiler

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug PhoenixProfilerTest.Router
end

defmodule PhoenixProfilerTest.EndpointDisabled do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler
  use PhoenixProfiler

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
end

defmodule PhoenixProfilerTest.EndpointNotConfigured do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler
end

Supervisor.start_link(
  [
    {PhoenixProfiler, name: PhoenixProfilerTest.Profiler},
    {Phoenix.PubSub, name: PhoenixProfilerTest.PubSub, adapter: Phoenix.PubSub.PG2},
    PhoenixProfilerTest.Endpoint,
    PhoenixProfilerTest.EndpointDisabled,
    PhoenixProfilerTest.EndpointNotConfigured
  ],
  strategy: :one_for_one
)

ExUnit.start()
