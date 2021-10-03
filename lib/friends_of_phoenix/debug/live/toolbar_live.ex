defmodule FriendsOfPhoenix.Debug.ToolbarLive do
  # The LiveView for the Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:main, class: "fophx-dbg"}
  alias FriendsOfPhoenix.Debug

  @token_key "fophx_debug"

  @impl Phoenix.LiveView
  def mount(_, %{@token_key => token}, socket) do
    socket = assign(socket, :token, token)
    socket = Debug.track(socket, token, %{kind: :toolbar})

    if connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(Debug.PubSub, Debug.Server.topic(token))
    end

    socket =
      case Debug.Server.info(token) do
        {:ok, info} ->
          assign_toolbar(socket, info)

        {:error, :not_started} ->
          assign_minimal_toolbar(socket)
      end

    {:ok, assign(socket, :exits, [])}
  end

  defp assign_minimal_toolbar(socket) do
    # Apply the minimal assigns when the debug server is not started.
    # Usually this occurs after a node has been restarted and
    # a request is received for a stale token.
    assign(socket, %{
      duration: nil,
      status: %{code: 0, phrase: "disconnected"},
      route_phrase: nil,
      vsn: Application.spec(:phoenix)[:vsn]
    })
  end

  defp assign_toolbar(socket, info) do
    route = route_info(info)

    assign(socket, %{
      duration: duration(info.duration),
      status: status(info.status),
      route_phrase: toolbar_text(socket, route),
      vsn: Application.spec(:phoenix)[:vsn]
    })
  end

  defp route_info(%{host: host, method: method, path_info: path, phoenix_router: router}) do
    Phoenix.Router.route_info(router, method, path, host)
  end

  # From LiveProfiler presence
  defp toolbar_text(%{kind: :profile, phoenix_live_action: action, view_module: lv}) do
    [inspect(lv), ?\s, inspect(action)]
  end

  defp toolbar_text(%{phoenix_live_view: {lv, _, _opts, _meta}, plug_opts: action})
       when is_atom(lv) and is_atom(action) do
    [inspect(lv), ?\s, inspect(action)]
  end

  defp toolbar_text(%{plug: controller, plug_opts: action}) when is_atom(action) do
    [inspect(controller), ?\s, inspect(action)]
  end

  defp toolbar_text(other) do
    IO.inspect(other, label: "unknown data for toolbar_text/1")
    ??
  end

  defp toolbar_text(%Phoenix.LiveView.Socket{} = socket, view) do
    toolbar_text(view) ++ [?\s, socket.assigns.token]
  end

  defp duration(duration) do
    duration = System.convert_time_unit(duration, :native, :microsecond)

    {value, unit} =
      if duration > 1000 do
        {duration |> div(1000) |> Integer.to_string(), "ms"}
      else
        {Integer.to_string(duration), "µs"}
      end

    %{value: value, unit: unit}
  end

  defp status(status_code) do
    %{code: status_code, phrase: Plug.Conn.Status.reason_phrase(status_code)}
  end

  @impl Phoenix.LiveView
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: _payload}, socket) do
    # TODO:
    # on :profile join -> monitor process
    # on :profile DOWN (abnormal) -> emerge errors on the toolbar
    presences =
      socket.assigns.token
      |> Debug.Server.topic()
      |> Debug.Presence.list()
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)

    view_or_nil = Enum.find(presences, &(&1.kind == :profile))

    socket = update_monitor(socket, view_or_nil)

    {:noreply, assign_view(socket, view_or_nil)}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:DOWN, ref, _, _pid, {:shutdown, :left}},
        %{private: %{monitor_ref: ref}} = socket
      ) do
    {:noreply, clear_monitor(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:DOWN, ref, _, _pid, reason},
        %{private: %{monitor_ref: ref}} = socket
      ) do
    exit_reason = {Phoenix.LiveView.Utils.random_id(), Exception.format_exit(reason)}
    socket = update(socket, :exits, &[exit_reason | &1])

    {:noreply, clear_monitor(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info(other, socket) do
    IO.inspect(other, label: "ToolbarLive received an unknown message")
    {:noreply, socket}
  end

  defp clear_monitor(%{private: private} = socket) do
    private = private |> Map.delete(:monitor_ref) |> Map.delete(:lv_pid)
    %{socket | private: private}
  end

  defp update_monitor(socket, nil) do
    socket
  end

  defp update_monitor(%{private: %{lv_pid: pid}} = socket, %{pid: pid}) do
    socket
  end

  defp update_monitor(%{private: %{monitor_ref: ref}} = socket, view) do
    Process.demonitor(ref)
    do_monitor_view(socket, view)
  end

  defp update_monitor(socket, view) do
    do_monitor_view(socket, view)
  end

  defp do_monitor_view(socket, %{pid: pid}) do
    ref = Process.monitor(pid)

    private =
      socket.private
      |> Map.put(:monitor_ref, ref)
      |> Map.put(:lv_pid, pid)

    %{socket | private: private}
  end

  defp assign_view(socket, nil), do: socket

  defp assign_view(socket, view) do
    new_phrase = toolbar_text(socket, view)
    assign(socket, :route_phrase, new_phrase)
  end
end
