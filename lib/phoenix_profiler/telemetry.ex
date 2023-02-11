defmodule PhoenixProfiler.Telemetry do
  # Telemetry helpers
  @moduledoc false

  live_view_events =
    for stage <- [:mount, :handle_params, :handle_event],
        action <- [:start, :stop, :exception] do
      [:phoenix, :live_view, stage, action]
    end

  plug_events = [
    [:phoenix, :endpoint, :stop],
    [:phxprof, :plug, :stop]
  ]

  @events plug_events ++ live_view_events

  @doc """
  Returns a list of built-in telemetry events to collect.
  """
  def events, do: @events

  @doc """
  Collector filter callback.
  """
  def collect(_, [:phoenix, :endpoint, :stop], %{duration: duration}, _meta) do
    {:keep, %{endpoint_duration: duration}}
  end

  def collect(_, [:phxprof, :plug, :stop], measures, %{conn: conn}) do
    profile = conn.private.phoenix_profiler

    case profile.info do
      :disable ->
        :skip

      info when info in [nil, :enable] ->
        {:keep,
         %{
           at: profile.system_time,
           conn: prune_values(conn),
           metrics: %{
             memory: collect_memory(conn.owner),
             total_duration: measures.duration
           }
         }}
    end
  end

  def collect(_, [:phoenix, :live_view | _] = event, measures, %{socket: socket} = meta) do
    cond do
      Map.has_key?(socket, :root_view) and socket.root_view == PhoenixProfiler.ToolbarLive ->
        :skip

      get_in(socket.private, [:root_view]) == PhoenixProfiler.ToolbarLive ->
        :skip

      true ->
        [_, _, _, action] = event

        data =
          socket
          |> Map.take([:root_view, :root_pid, :router])
          |> Map.put(:live_action, socket.assigns[:live_action])
          |> Map.put_new(:root_view, socket.private[:root_view])
          |> Map.put(:connected?, Phoenix.LiveView.connected?(socket))
          |> Map.merge(measures)

        data =
          if action == :exception do
            meta
            |> Map.take([:kind, :reason])
            |> Map.put(:stacktrace, Map.get(meta, :stacktrace, []))
            |> Map.merge(data)
          else
            data
          end

        {:keep, data}
    end
  end

  def collect(_, _, _, _), do: :keep

  @kB 1_024
  defp collect_memory(pid) when is_pid(pid) do
    {:memory, bytes} = Process.info(pid, :memory)
    div(bytes, @kB)
  end

  @phoenix_private_keys [
    :phoenix_action,
    :phoenix_controller,
    :phoenix_endpoint,
    :phoenix_flash,
    :phoenix_format,
    :phoenix_layout,
    :phoenix_root_layout,
    :phoenix_router,
    :phoenix_view
  ]
  defp prune_values(%Plug.Conn{} = conn) do
    conn = conn |> Plug.Conn.delete_req_header("cookie")

    %{
      conn
      | cookies: %{},
        req_cookies: %{},
        resp_body: nil,
        assigns: Map.delete(conn.assigns, :content),
        private: Map.take(conn.private, @phoenix_private_keys)
    }
  end
end
