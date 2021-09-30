defmodule FriendsOfPhoenix.Debug.ToolbarLive do
  # The LiveView for the Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:main, class: "fophx-dbg"}
  alias FriendsOfPhoenix.Debug

  @token_key "fophx_debug"

  def mount(_, %{@token_key => token}, socket) do
    %{Debug => info} = Debug.entries(token)
    route = route_info(info)

    {:ok,
     assign(socket, %{
       duration: duration(info.duration),
       status: status(info.status),
       route_phrase: toolbar_text(route),
       vsn: Application.spec(:phoenix)[:vsn]
     })}
  end

  defp route_info(%{host: host, method: method, path_info: path, phoenix_router: router}) do
    Phoenix.Router.route_info(router, method, path, host)
  end

  defp route_info(other) do
    raise ArgumentError, """
    Expected DebugBar entry from plug, got:

        #{inspect(other)}
    """
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
end
