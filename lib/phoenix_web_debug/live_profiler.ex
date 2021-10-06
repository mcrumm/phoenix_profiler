defmodule PhoenixWeb.LiveProfiler do
  @moduledoc """
  Interactive profiler for LiveView processes.

  LiveProfiler performs two roles:

  * As a Plug, to inject the debug token into the session of the
    stateless HTTP response.

  * As a LiveView lifecycle hook, to enable introspection of
    the process under live profiling.

  ## As a Plug

  As a Plug, LiveProfiler lives at the bottom of the `:browser` pipeline
  on your Router module, typically found in `lib/my_app_web/router.ex`:

      pipeline :browser do
        # plugs...
        if Mix.env() == :dev do
          plug PhoenixWeb.LiveProfiler
        end
      end

  ## As a lifecycle hook

  As a LiveView lifecycle hook, LiveProfiler lives on a
  module where you `use LiveView`:

      if Mix.env() == :dev do
        on_mount {PhoenixWeb.LiveProfiler, __MODULE__}
      end

  See the LiveView Profiling section of the [`Profiler`](`PhoenixWeb.Profiler`) module docs.

  """
  import Phoenix.LiveView
  alias PhoenixWeb.Profiler

  @behaviour Plug

  @private_key :pwdt
  @session_key Atom.to_string(@private_key)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{private: %{@private_key => token}} = conn, _) do
    Plug.Conn.put_session(conn, @session_key, token)
  end

  def call(conn, _), do: conn

  def on_mount(view_module, params, %{@session_key => token} = session, socket) do
    apply_profiler_hooks(socket, connected?(socket), view_module, token, params, session)
  end

  def on_mount(_view_module, _params, _session, socket) do
    {:cont, socket}
  end

  defp apply_profiler_hooks(socket, _connected? = false, _view_module, _token, _params, _session) do
    {:cont, socket}
  end

  defp apply_profiler_hooks(socket, _connected? = true, view_module, token, _params, _session) do
    Profiler.track(socket, token, %{
      kind: :profile,
      phoenix_live_action: socket.assigns.live_action,
      root_view: socket.private[:root_view],
      transport_pid: transport_pid(socket),
      view_module: view_module
    })

    {:cont, socket}
  end
end
