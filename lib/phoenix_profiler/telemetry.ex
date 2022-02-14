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
  Helper to register the current process as a collector.
  """
  def register(server, pid) when is_pid(pid) do
    server
    |> PhoenixProfiler.Supervisor.debug_name()
    |> DebugThing.Collector.collect(pid)
  end

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
           conn: %{conn | resp_body: nil, assigns: Map.delete(conn.assigns, :content)},
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
          |> Map.take([:root_view, :root_pid])
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

  @doc """
  Returns the child specification to start the profiler
  under a supervision tree.
  """
  def child_spec(opts) do
    {name, _opts} = Keyword.pop(opts, :name)

    unless name do
      raise ArgumentError, ":name is required to start the profiler telemetry"
    end

    %{
      id: name,
      start:
        {DebugThing, :start_link,
         [[filter: &__MODULE__.collect/4, name: name, telemetry: @events]]}
    }
  end

  @doc """
  Executes the collector event for `info` for the current process.
  """
  defdelegate collector_info_exec(info), to: DebugThing.Telemetry

  @doc """
  Starts the collector sidecar for a given `pid`.
  """
  defdelegate start_collector(server, pid, arg \\ nil, info \\ :enable), to: DebugThing

  @doc """
  Reduces over telemetry events in a given `collector_pid`.
  """
  defdelegate reduce(collector_pid, initial, func), to: DebugThing.Collector

  @doc """
  Updates the collector info for `pid` for the current process.
  """
  defdelegate update_collector_info(pid, func), to: DebugThing.Registry
end
