defmodule DemoWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DemoWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PhoenixWeb.LiveProfiler
  end

  scope "/", DemoWeb do
    pipe_through :browser
    get "/", PageController, :index
    get "/hello", PageController, :hello
    get "/hello/:name", PageController, :hello
    live "/app", AppLive.Index, :index
  end
end
