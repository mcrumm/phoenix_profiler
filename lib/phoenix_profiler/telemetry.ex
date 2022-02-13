defmodule PhoenixProfiler.Telemetry do
  # Telemetry helpers
  @moduledoc false

  live_view_events =
    for stage <- [:mount, :handle_params, :handle_event],
        action <- [:start, :stop, :exception] do
      [:phoenix, :live_view, stage, action]
    end

  @events live_view_events

  @doc """
  Returns a list of built-in telemetry events to collect.
  """
  def events, do: @events

  @doc """
  Helper to register the current process as a collector.
  """
  def collector(server, pid) do
    server
    |> PhoenixProfiler.Supervisor.debug_name()
    |> DebugThing.Collector.collect(pid)
  end

  @doc """
  Collector filter callback.
  """
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
end
