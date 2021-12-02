defmodule PhoenixWeb.Profiler.Routes do
  # Router introspection for the profiler
  @moduledoc false

  @doc """
  Returns route info, or sparse data if a router was not used.
  """
  def route_info(%Plug.Conn{} = conn) do
    case conn.private do
      %{phoenix_router: router} ->
        Phoenix.Router.route_info(
          router,
          conn.method,
          conn.request_path,
          conn.host
        )

      _ ->
        %{
          log: false,
          path_params: %{},
          pipe_through: [],
          plug: nil,
          plug_opts: nil,
          route: conn.request_path
        }
    end
  end

  # From LiveViewListener telemetry
  def plug_action(%{root_pid: _, live_action: action, root_view: lv}) do
    {lv, action}
  end

  # LiveView from Router
  def plug_action(%{phoenix_live_view: {lv, _, _opts, _meta}, plug_opts: action})
      when is_atom(lv) and is_atom(action) do
    {lv, action}
  end

  # Controller::action
  def plug_action(%{plug: controller, plug_opts: action}) when is_atom(action) do
    {controller, action}
  end

  # Other plugs
  def plug_action(%{plug: plug, plug_opts: opts}) when is_list(opts) do
    {plug, opts}
  end

  def plug_action(other) do
    IO.warn("""
    unknown data for plug action, got:

        #{inspect(other)}

    """)

    {nil, nil}
  end

  def guess_helper(router, route) do
    plug_action = plug_action(route)

    helper =
      case plug_action do
        {nil, nil} ->
          nil

        {plug, action} ->
          plug_parts = Module.split(plug)

          prefix =
            if router do
              router
              |> Module.split()
              |> Enum.reverse()
              |> tl()
              |> Enum.reverse()
            else
              []
            end

          # Builds the string "Plug :action"
          # Attempts to remove the module path shared with the
          # corresponding Phoenix Router.
          Enum.intersperse(plug_parts -- prefix, ?.) ++ [?\s, inspect(action)]
      end

    {plug, action} = plug_action
    {helper, plug, action}
  end
end
