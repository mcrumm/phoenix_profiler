defmodule PhoenixWeb.LiveProfiler do
  @moduledoc """
  Interactive profiler for LiveView processes.
  """
  import Phoenix.LiveView
  alias PhoenixWeb.Debug

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
    apply_debug_hooks(socket, connected?(socket), view_module, token, params, session)
  end

  def on_mount(_view_module, _params, _session, socket) do
    {:cont, socket}
  end

  defp apply_debug_hooks(socket, _connected? = false, _view_module, _token, _params, _session) do
    {:cont, socket}
  end

  defp apply_debug_hooks(socket, _connected? = true, view_module, token, _params, _session) do
    Debug.track(socket, token, %{
      kind: :profile,
      phoenix_live_action: socket.assigns.live_action,
      root_view: socket.private[:root_view],
      transport_pid: transport_pid(socket),
      view_module: view_module
    })

    {:cont, socket}
  end
end
