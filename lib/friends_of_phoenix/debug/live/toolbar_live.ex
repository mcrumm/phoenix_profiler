defmodule FriendsOfPhoenix.Debug.ToolbarLive do
  # The LiveView for the Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:div, [class: "phxweb-toolbar-view"]}
  alias FriendsOfPhoenix.Debug

  @token_key "fophx_debug"

  @impl Phoenix.LiveView
  def mount(_, %{@token_key => token}, %{private: private} = socket) do
    socket = assign(socket, :token, token)
    socket = Debug.track(socket, token, %{kind: :toolbar})

    if connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(Debug.PubSub, Debug.Server.topic(token))
    end

    socket =
      case Debug.Server.info(token) do
        {:ok, info} ->
          socket = %{socket | private: Map.put(private, :debuginfo, info)}
          assign_toolbar(socket, info)

        {:error, :not_started} ->
          assign_minimal_toolbar(socket)
      end

    {:ok, assign(socket, display: "block", exits: [], exits_count: 0, system: system()),
     temporary_assigns: [exits: []]}
  end

  defp assign_minimal_toolbar(socket) do
    # Apply the minimal assigns when the debug server is not started.
    # Usually this occurs after a node has been restarted and
    # a request is received for a stale token.
    assign(socket, %{
      duration: nil,
      request: %{
        class: "disconnected",
        status_code: ":|",
        status_phrase: "No Debug Session (refresh)",
        plug: "n/a",
        action: "n/a",
        plug_action: nil
      }
    })
  end

  defp assign_toolbar(socket, info) do
    socket
    |> apply_request(info)
    |> update_view(route_info(info))
    |> assign(:duration, duration(info.duration))
  end

  defp apply_request(socket, %{status: status}) do
    assign(socket, :request, %{
      class: request_class(status),
      plug: nil,
      action: nil,
      plug_action: nil,
      status_code: status,
      status_phrase: Plug.Conn.Status.reason_phrase(status)
    })
  end

  defp update_view(socket, route) do
    update(socket, :request, fn req ->
      {plug, action} = plug_action = plug_action(route)

      short_name =
        case plug_action do
          {nil, nil} ->
            nil

          {plug, action} ->
            plug_parts = Module.split(plug)

            prefix =
              socket.private.debuginfo.phoenix_router
              |> Module.split()
              |> Enum.reverse()
              |> tl()
              |> Enum.reverse()

            # Builds the string "Plug :action"
            # Attempts to remove the module path shared with the
            # corresponding Phoenix Router.
            (plug_parts -- prefix) ++ [?\s, inspect(action)]
        end

      %{req | plug: inspect(plug), action: inspect(action), plug_action: short_name}
    end)
  end

  defp route_info(info) when map_size(info) == 0, do: %{}

  defp route_info(%{host: host, method: method, path_info: path, phoenix_router: router}) do
    Phoenix.Router.route_info(router, method, path, host)
  end

  # From LiveProfiler presence
  defp plug_action(%{kind: :profile, phoenix_live_action: action, view_module: lv}) do
    {lv, action}
  end

  defp plug_action(%{phoenix_live_view: {lv, _, _opts, _meta}, plug_opts: action})
       when is_atom(lv) and is_atom(action) do
    {lv, action}
  end

  defp plug_action(%{plug: controller, plug_opts: action}) when is_atom(action) do
    {controller, action}
  end

  defp plug_action(other) do
    IO.warn("""
    unknown data for plug action, got:

        #{inspect(other)}

    """)

    {nil, nil}
  end

  defp duration(duration) do
    duration = System.convert_time_unit(duration, :native, :microsecond)

    if duration > 1000 do
      value = duration |> div(1000) |> Integer.to_string()
      %{value: value, label: "ms", phrase: "#{value} milliseconds"}
    else
      value = Integer.to_string(duration)
      %{value: value, label: "µs", phrase: "#{value} microseconds"}
    end
  end

  defp request_class(code) when is_integer(code) do
    case code do
      code when code >= 200 and code < 300 -> :green
      code when code >= 400 and code < 500 -> :red
      code when code >= 500 and code < 600 -> :red
      _ -> nil
    end
  end

  defp system do
    %{
      elixir_version: System.version(),
      phoenix_version: Application.spec(:phoenix)[:vsn],
      live_view_version: Application.spec(:phoenix_live_view)[:vsn],
      otp_release: System.otp_release()
    }
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
    exit_reason = %{
      ref: Phoenix.LiveView.Utils.random_id(),
      reason: Exception.format_exit(reason),
      at: Time.utc_now() |> Time.truncate(:second)
    }

    socket =
      socket
      |> update(:exits, &[exit_reason | &1])
      |> update(:exits_count, &(&1 + 1))

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
    update_view(socket, view)
  end
end
