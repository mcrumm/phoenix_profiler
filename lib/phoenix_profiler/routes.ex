defmodule PhoenixProfiler.Routes do
  # Router introspection for the profiler
  @moduledoc false

  @route_not_found {:route_not_found, nil, nil}
  @router_not_set {:router_not_set, nil, nil}

  @doc """
  Returns route information from the given `conn`.

  If no router is set on the conn, returns `#{inspect(@router_not_set)}`.

  If the route cannot be determined, returns `#{inspect(@route_not_found)}`.

  Otherwise, this function returns a tuple of `{helper, plug_or_live_view, action_or_plug_opts}`.
  """
  def info(node \\ node(), conn)

  def info(node, %Plug.Conn{private: %{phoenix_router: router}} = conn) do
    case route_info(node, router, conn.method, conn.request_path, conn.host) do
      :error -> @route_not_found
      route_info -> info(node, router, route_info)
    end
  end

  def info(_, %Plug.Conn{}), do: @router_not_set

  @doc """
  Returns information about the given route.

  See `info/2`.
  """
  def info(node, router, route_info)

  def info(_, nil, _), do: @router_not_set

  def info(node, router, route_info) when is_atom(router) do
    case routes(node, router) do
      :error -> @route_not_found
      routes -> match_router_helper(routes, route_info)
    end
  end

  defp match_router_helper([], _), do: @route_not_found

  defp match_router_helper(routes, route_info) when is_list(routes) do
    Enum.find_value(routes, @route_not_found, &route(&1, route_info))
  end

  defp route_info(node, router, method, request_path, host) do
    case :rpc.call(node, Phoenix.Router, :route_info, [router, method, request_path, host]) do
      {:badrpc, _} -> :error
      other -> other
    end
  end

  defp routes(node, router) do
    # Replace with call to Phoenix.Router.routes/1 when we require Phoenix v1.6+.
    case :rpc.call(node, router, :__routes__, []) do
      {:badrpc, _} -> :error
      routes -> routes
    end
  end

  # route_info from LiveViewListener telemetry
  defp route(
         %{metadata: %{phoenix_live_view: {lv, action, _opts, _extra}}} = route,
         %{root_pid: _, root_view: lv, live_action: action}
       ) do
    {route.helper, lv, route.plug_opts}
  end

  # Live route
  defp route(
         %{path: path, metadata: %{phoenix_live_view: {lv, action, _, _}}} = route,
         %{route: path, phoenix_live_view: {lv, action, _, _}}
       ) do
    {route.helper, lv, route.plug_opts}
  end

  # Plug route
  defp route(
         %{path: path, plug: plug, plug_opts: plug_opts} = route,
         %{route: path, plug: plug, plug_opts: plug_opts}
       ) do
    {route.helper, plug, plug_opts}
  end

  defp route(_, _), do: nil
end
