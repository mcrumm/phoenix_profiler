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
      ~r"dev/templates/.*(eex)$",
      ~r"dev/templates/page/*.heex$",
      ~r"dev.exs$"
    ]
  ],
  phoenix_profiler: true
)

defmodule DemoWeb.ErrorView do
  use Phoenix.View, root: "dev/templates", namespace: DemoWeb

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule DemoWeb.LayoutView do
  use Phoenix.View, root: "dev/templates", namespace: DemoWeb
  use Phoenix.HTML

  import Phoenix.Controller,
    only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

  import Phoenix.LiveView.Helpers
  import Phoenix.View
  alias DemoWeb.Router.Helpers, as: Routes
end

defmodule DemoWeb.PageController do
  use Phoenix.Controller, namespace: DemoWeb
  import Plug.Conn

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def hello(conn, %{"name" => name}) do
    render(conn, "hello.html", name: name)
  end

  def hello(conn, _params) do
    render(conn, "hello.html", name: "friend")
  end
end

defmodule DemoWeb.PageView do
  use Phoenix.View, root: "dev/templates", namespace: DemoWeb
  use Phoenix.Component
  use Phoenix.HTML
  import Phoenix.LiveView.Helpers
  import Phoenix.View
  alias DemoWeb.Router.Helpers, as: Routes

  def render("index.html", assigns) do
    ~H"""
    <h1>Phoenix Web Profiler Dev</h1>
    <p>Welcome, devs!</p>
    <h2>Links</h2>
    <ul>
      <li><%= link "Profile IndexController, :hello", to: Routes.page_path(DemoWeb.Endpoint, :hello) %></li>
      <li><%= link "Profile IndexController, :hello with param", to: Routes.page_path(DemoWeb.Endpoint, :hello, name: "dev") %></li>
      <li><%= link "Profile ErrorView: assign not available", to: Routes.errors_path(DemoWeb.Endpoint, :assign_not_available) %></li>
      <li><%= link "Profile AppLive.Index, :index", to: Routes.app_index_path(DemoWeb.Endpoint, :index) %></li>
    </ul>
    """
  end

  def render("hello.html", assigns) do
    ~H"""
    <hello>Hello, <%= @name %>!</hello>
    """
  end
end

defmodule DemoWeb.ErrorsController do
  use Phoenix.Controller, namespace: DemoWeb
  import Plug.Conn

  def assign_not_available(conn, _) do
    render(conn, "assign_not_available.html", %{})
  end
end

defmodule DemoWeb.ErrorsView do
  use Phoenix.View, root: "dev/templates", namespace: DemoWeb
  use Phoenix.HTML

  def render("assign_not_available.html", assigns) do
    ~E"""
    <p><%= @not_available %></p>
    """
  end
end

defmodule DemoWeb.AppLive.Index do
  use Phoenix.LiveView, layout: {DemoWeb.LayoutView, "live.html"}
  alias DemoWeb.Router.Helpers, as: Routes

  on_mount PhoenixProfiler

  def mount(_, _, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  def render(assigns) do
    ~L"""
    <section class="live">
      <h2>AppLive Page</h2>
      <p>Action=<%= @live_action %></p>
      <p>Count=<%= @count %></p>
      <button phx-click="plus">+</button><button phx-click="minus">-</button>
      <p>Links:</p>
      <ul>
        <li><%= live_redirect "Navigate to :index", to: Routes.app_index_path(@socket, :index) %></li>
        <li><%= live_redirect "Navigate to :foo", to: Routes.app_index_path(@socket, :foo) %></li>
      </ul>
    </section>
    """
  end

  def handle_event("plus", _, socket) do
    {:noreply,
     update(socket, :count, fn i ->
       i = i + 1
       i
     end)}
  end

  def handle_event("minus", _, socket) do
    {:noreply,
     update(socket, :count, fn i ->
       i = i - 1
       i
     end)}
  end
end

defmodule DemoWeb.PlugRouter do
  use Plug.Router
  import Phoenix.Controller

  plug :match
  plug :dispatch

  get "/" do
    html(conn, "<html><body>PlugRouter::Home</body></html>")
  end

  match _ do
    html(conn, "<html><body>PlugRouter::Not Found</body></html>")
  end
end

defmodule DemoWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DemoWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", DemoWeb do
    pipe_through :browser
    get "/", PageController, :index
    get "/hello", PageController, :hello
    get "/hello/:name", PageController, :hello
    get "/errors/assign-not-available", ErrorsController, :assign_not_available
    live "/app", AppLive.Index, :index
    live "/app/foo", AppLive.Index, :foo

    forward "/plug-router", PlugRouter

    live_dashboard "/dashboard",
      additional_pages: [
        _profiler: PhoenixProfiler.dashboard()
      ]
  end
end

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
