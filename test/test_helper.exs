Application.put_env(:phoenix_web_profiler, PhoenixWeb.ProfilerTest.Endpoint,
  url: [host: "localhost", port: 4000],
  secret_key_base: "LIyk9co9Mt8KowH/g1WeMkufq/9Bz1XuEZMhCZAwnBc7VFKCfkDq/vRw+Xso4Q0q",
  live_view: [signing_salt: "NbA2FdHo"],
  render_errors: [view: PhoenixWeb.ProfilerTest.ErrorView],
  check_origin: false,
  pubsub_server: PhoenixWeb.ProfilerTest.PubSub
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
    plug PhoenixWeb.LiveProfiler
  end
end

defmodule PhoenixWeb.ProfilerTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_web_profiler

  plug PhoenixWeb.Profiler

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug PhoenixWeb.ProfilerTest.Router
end

Supervisor.start_link(
  [
    {Phoenix.PubSub, name: PhoenixWeb.ProfilerTest.PubSub, adapter: Phoenix.PubSub.PG2},
    PhoenixWeb.ProfilerTest.Endpoint
  ],
  strategy: :one_for_one
)

ExUnit.start(exclude: :integration)
