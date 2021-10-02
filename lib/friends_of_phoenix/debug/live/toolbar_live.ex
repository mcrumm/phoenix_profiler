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

    case Debug.Server.info(token) do
      {:ok, info} ->
        assign_toolbar(socket, info)

      {:error, :not_started} ->
        assign_minimal_toolbar(socket)
    end
  end

  defp assign_minimal_toolbar(socket) do
    # Apply the minimal assigns when the debug server is not started.
    # Usually this occurs after a node has been restarted and
    # a request is received for a stale token.
    {:ok,
     assign(socket, %{
       duration: nil,
       status: nil,
       route_phrase: "refresh to reconnect (ref:#{socket.assigns.token})",
       vsn: Application.spec(:phoenix)[:vsn]
     })}
  end

  defp assign_toolbar(socket, info) do
    route = route_info(info)

    {:ok,
     assign(socket, %{
       duration: duration(info.duration),
       status: status(info.status),
       route_phrase: toolbar_text(socket, route),
       vsn: Application.spec(:phoenix)[:vsn]
     })}
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

    {:noreply, assign_view(socket, view_or_nil)}
  end

  defp assign_view(socket, nil), do: socket

  defp assign_view(socket, view) do
    new_phrase = toolbar_text(socket, view)
    assign(socket, :route_phrase, new_phrase)
  end
end
