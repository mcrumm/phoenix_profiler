defmodule PhoenixProfilerWeb.Routes do
  # Router introspection for the profiler
  @moduledoc false

  @doc """
  Attempts to guess the router helper used for a given `conn`.
  """
  def guess_router_helper(%Plug.Conn{private: %{phoenix_router: router}} = conn) do
    case Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host) do
      :error -> {:route_not_found, nil, nil}
      route_info -> guess_router_helper(Phoenix.Router.routes(router), route_info)
    end
  end

  def guess_router_helper(%Plug.Conn{}), do: {:router_not_set, nil, nil}

  def guess_router_helper(nil, _), do: {:router_not_set, nil, nil}

  def guess_router_helper(router, route_info) when is_atom(router) do
    router |> Phoenix.Router.routes() |> guess_router_helper(route_info)
  end

  # From LiveViewListener telemetry
  def guess_router_helper(routes, %{root_pid: _, live_action: action, root_view: lv})
      when is_list(routes) do
    matches =
      for %{metadata: %{phoenix_live_view: {^lv, ^action, _opts, _extra}}} = route <- routes,
          do: {route.helper, route.plug, route.plug_opts}

    case matches do
      [helper] -> helper
      [] -> {:route_not_found, nil, nil}
    end
  end

  def guess_router_helper(routes, %{route: path, plug: plug, plug_opts: plug_opts})
      when is_list(routes) do
    matches =
      for %{path: ^path, plug: ^plug, plug_opts: ^plug_opts} = route <- routes,
          do: {route.helper, plug, plug_opts}

    case matches do
      [helper] -> helper
      [] -> {:route_not_found, nil, nil}
    end
  end
end
