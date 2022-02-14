defmodule PhoenixProfiler.TelemetryServer do
  @moduledoc false
  use GenServer
  alias PhoenixProfiler.TelemetryCollector
  alias PhoenixProfiler.TelemetryRegistry

  @disable_event [:phoenix_profiler, :internal, :collector, :disable]
  @enable_event [:phoenix_profiler, :internal, :collector, :enable]

  def start_link(opts) do
    config = Enum.into(opts, %{})
    config = Map.put_new(config, :events, [])
    config = Map.put_new(config, :filter, fn _, _, _, _ -> :keep end)
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Executes the collector event for `info` for the current process.
  """
  def collector_info_exec(:disable), do: telemetry_exec(@disable_event)
  def collector_info_exec(:enable), do: telemetry_exec(@enable_event)

  defp telemetry_exec(event) do
    :telemetry.execute(event, %{system_time: System.system_time()}, %{})
  end

  @impl true
  def init(%{events: events, filter: filter, server: server}) do
    Process.flag(:trap_exit, true)

    :telemetry.attach_many(
      {__MODULE__, self()},
      events ++ [@disable_event, @enable_event],
      &__MODULE__.handle_execute/4,
      %{filter: filter, server: server}
    )

    {:ok, events}
  end

  @doc """
  Forwards telemetry events to a registered collector, if it exists.
  """
  def handle_execute([_, _, _, info] = event, _, _, %{server: server})
      when event in [@disable_event, @enable_event] do
    case TelemetryRegistry.lookup(server) do
      {:ok, {pid, {^server, _, old_info}}} when old_info !== info ->
        TelemetryCollector.update_info(pid, fn _ -> info end)

      _ ->
        :ok
    end
  end

  def handle_execute(event, measurements, metadata, %{filter: filter, server: server}) do
    with {:ok, {pid, {^server, arg, :enable}}} <- TelemetryRegistry.lookup(server) do
      # todo: ensure span ref is set on data (or message) if it exists
      data = filter_event(filter, arg, event, measurements, metadata)
      event_ts = measurements[:system_time] || System.system_time()

      if data do
        send(pid, {:telemetry, arg, event, event_ts, data})
      end
    end
  end

  defp filter_event(filter, arg, event, measurements, metadata) do
    # todo: rescue/catch, detach telemetry, and warn on error
    case filter.(arg, event, measurements, metadata) do
      :keep -> %{}
      {:keep, data} when is_map(data) -> data
      :skip -> nil
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach({__MODULE__, self()})
    :ok
  end
end
