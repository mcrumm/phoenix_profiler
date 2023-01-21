defmodule PhoenixProfiler.TelemetryServer do
  @moduledoc false
  use GenServer
  alias PhoenixProfiler.TelemetryCollector
  alias PhoenixProfiler.TelemetryRegistry

  @doc """
  Starts a collector for `server` for a given `pid`.
  """
  def listen(server, pid), do: listen(server, pid, nil, :enable)
  def listen(server, pid, arg), do: listen(server, pid, arg, :enable)
  def listen(server, pid, arg, info), do: listen(node(), server, pid, arg, info)

  def listen(node, server, pid, arg, info)
      when is_pid(pid) and is_atom(info) and info in [:disable, :enable] do
    DynamicSupervisor.start_child(
      {PhoenixProfiler.DynamicSupervisor, node},
      {PhoenixProfiler.TelemetryCollector, {server, pid, arg, info}}
    )
  end

  @doc """
  Disables the collector for `key` if it exists.
  """
  def disable_key(server, key) do
    case TelemetryRegistry.lookup_key(server, key) do
      {:ok, {pid, {_, _, :enable}}} ->
        TelemetryCollector.disable(pid)

      {:ok, _} ->
        :ok

      :error ->
        :error
    end
  end

  @doc """
  Enables the collector for `key` if it exists.
  """
  def enable_key(server, key) do
    case TelemetryRegistry.lookup_key(server, key) do
      {:ok, {pid, {_, _, :disable}}} ->
        TelemetryCollector.enable(pid)

      {:ok, _} ->
        :ok

      :error ->
        :error
    end
  end

  @doc """
  Starts a telemetry server linked to the current process.
  """
  def start_link(opts) do
    config = Enum.into(opts, %{})
    config = Map.put_new(config, :events, [])
    config = Map.put_new(config, :filter, fn _, _, _, _ -> :keep end)
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(%{events: events, filter: filter, server: server}) do
    Process.flag(:trap_exit, true)

    :telemetry.attach_many(
      {__MODULE__, self()},
      events,
      &__MODULE__.handle_execute/4,
      %{filter: filter, server: server}
    )

    {:ok, events}
  end

  @doc """
  Forwards telemetry events to a registered collector, if it exists.
  """
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
