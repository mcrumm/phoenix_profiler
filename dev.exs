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
      ~r"dev/templates/.*(eex)$"
    ]
  ],
  phoenix_profiler: [server: DemoWeb.Profiler]
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

  def live(conn, _params) do
    render(conn, "live.html")
  end

  def disabled(conn, _params) do
    conn = PhoenixProfiler.disable(conn)
    render(conn, "disabled.html")
  end
end

defmodule DemoWeb.PageView do
  use Phoenix.View, root: "dev/templates", namespace: DemoWeb
  use Phoenix.Component
  use Phoenix.HTML
  import Phoenix.View
  alias DemoWeb.Router.Helpers, as: Routes

  def render("index.html", assigns) do
    ~H"""
    <h1>Phoenix Web Profiler Dev</h1>
    <p>Welcome, devs!</p>
    <h2>Stateless Profiles</h2>
    <ul>
      <li><%= link "Profile PageController, :hello", to: Routes.page_path(DemoWeb.Endpoint, :hello) %></li>
      <li><%= link "Profile PageController, :hello with param", to: Routes.page_path(DemoWeb.Endpoint, :hello, name: "dev") %></li>
      <li><%= link "Profile ErrorsController: assign not available", to: Routes.errors_path(DemoWeb.Endpoint, :assign_not_available) %></li>
    </ul>
    <h2>Live Profiles</h2>
    <ul>
      <li><%= link "Profile PageController, :live", to: Routes.page_path(DemoWeb.Endpoint, :live) %></li>
      <li><%= link "Profile AppLive.Index, :index", to: Routes.app_index_path(DemoWeb.Endpoint, :index) %></li>
    </ul>
    <h2>Controls</h2>
    <ul>
      <li><%= link "Disable: PageController, :disabled should not be profiled", to: Routes.page_path(DemoWeb.Endpoint, :disabled) %></li>
    </ul>
    """
  end

  def render("hello.html", assigns) do
    ~H"""
    <hello>Hello, <%= @name %>!</hello>
    """
  end

  def render("disabled.html", assigns) do
    ~H"""
    <p>This request <em>is not profiled</em>.</p>
    """
  end

  def render("live.html", assigns) do
    ~H"""
    <div>
      <%= live_render(@conn, EmbeddedLive.Switch, id: "hallway", session: %{"name" => "hall_lights", "state" => "on"}) %>
      <%= live_render(@conn, EmbeddedLive.Switch, id: "kitchen", session: %{"name" => "kitchen_lights", "state" => "on"}) %>
    </div>
    """
  end
end

defmodule EmbeddedLive.Switch do
  use Phoenix.LiveView, layout: {DemoWeb.LayoutView, "live.html"}

  on_mount PhoenixProfiler

  def render(assigns) do
    ~H"""
    <div style="display:flex;align-items:baseline;">
      <a href="javascript:void(0);" phx-click="toggle" phx-click-value={@value}>
        <%= @label <> " " <> (if @checked, do: "on", else: "off") %>
      </a>
    </div>
    """
  end

  def handle_event("toggle", _, socket) do
    {:noreply, update(socket, :checked, &(!&1))}
  end

  def mount(_, session, socket) do
    socket = assign_new(socket, :name, fn -> session["name"] || "checkbox" end)

    socket =
      socket
      |> assign_new(:id, fn ->
        session["id"] || "chk#{String.capitalize(socket.assigns.name)}"
      end)
      |> assign_new(:label, fn ->
        session["label"] || Phoenix.Naming.humanize(socket.assigns.name)
      end)
      |> assign(:value, "PID#{:erlang.pid_to_list(self())}")
      |> assign_new(:checked, fn -> checked(session["state"]) end)

    {:ok, socket, layout: false}
  end

  defp checked("on"), do: true
  defp checked("off"), do: false
  defp checked(_), do: false
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
  use Phoenix.HTML
  alias DemoWeb.Router.Helpers, as: Routes

  on_mount PhoenixProfiler

  def mount(_, _, socket) do
    {:ok, socket |> assign(:count, 0) |> apply_profiler_toggle()}
  end

  def handle_params(params, _, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, _, _) do
    {:noreply, socket}
  end

  defp apply_profiler_toggle(socket) do
    if connected?(socket) do
      info = socket.private.phoenix_profiler_info
      next = if info == :enable, do: :disable, else: :enable
      assign(socket, :toggle_text, String.capitalize(to_string(next)) <> " Profiler")
    else
      assign(socket, :toggle_text, nil)
    end
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
      <p>Controls:</p>
      <%= if @toggle_text do %>
      <div><button phx-click="toggle-profiler"><%= @toggle_text %></button></div>
      <% end %>
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

  def handle_event("toggle-profiler", _, socket) do
    info = socket.private.phoenix_profiler_info
    next = if info == :enable, do: :disable, else: :enable
    socket = apply(PhoenixProfiler, next, [socket])

    {:noreply, apply_profiler_toggle(socket)}
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
    get "/disabled", PageController, :disabled
    get "/errors/assign-not-available", ErrorsController, :assign_not_available
    get "/live-render", PageController, :live
    live "/app", AppLive.Index, :index
    live "/app/foo", AppLive.Index, :foo

    forward "/plug-router", PlugRouter

    live_dashboard "/dashboard",
      additional_pages: [
        _profiler: {PhoenixProfiler.Dashboard, []}
      ]
  end
end

defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_profiler
  use PhoenixProfiler

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
    {PhoenixProfiler, name: DemoWeb.OtherProfiler},
    {PhoenixProfiler, name: DemoWeb.Profiler},
    {Phoenix.PubSub, [name: Demo.PubSub, adapter: Phoenix.PubSub.PG2]},
    DemoWeb.Endpoint
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  Process.sleep(:infinity)
end)
