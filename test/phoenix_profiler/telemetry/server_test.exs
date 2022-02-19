defmodule PhoenixProfiler.TelemetryServerTest do
  use ExUnit.Case
  alias PhoenixProfiler.TelemetryServer
  doctest TelemetryServer

  describe "listen/2" do
    test "starts a collector pid" do
      start_supervised!(
        {TelemetryServer, server: name = unique_debug_name(), events: [[:debug, :me]]}
      )

      {:ok, collector_pid} = TelemetryServer.listen(name, self())
      assert Process.alive?(collector_pid)

      Process.exit(collector_pid, :normal)
    end

    test "returns {:error, {:already_registered, pid()}} when already registered" do
      start_supervised!(
        {TelemetryServer, server: name = unique_debug_name(), events: [[:debug, :me]]}
      )

      {:ok, collector_pid} = TelemetryServer.listen(name, self())

      assert TelemetryServer.listen(name, self()) ==
               {:error, {:already_registered, collector_pid}}

      Process.exit(collector_pid, :normal)
    end

    test "receives telemetry for self" do
      name = unique_debug_name()
      start_supervised!({TelemetryServer, server: name, events: [[:debug, name]]})

      {:ok, collector_pid} = TelemetryServer.listen(name, self())

      :ok = :telemetry.execute([:debug, name], %{system_time: 1}, %{})
      :ok = :telemetry.execute([:debug, name], %{system_time: 2}, %{})
      :ok = :telemetry.execute([:debug, name], %{system_time: 3}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, name]},
               {2, [:debug, name]},
               {3, [:debug, name]}
             ]

      Process.exit(collector_pid, :normal)
    end

    test "receives telemetry for $callers" do
      name = unique_debug_name()
      start_supervised!({TelemetryServer, server: name, events: [[:debug, :me]]})

      {:ok, collector_pid} = TelemetryServer.listen(name, self())

      :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      :telemetry.execute([:debug, :me], %{system_time: 2}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, :me]},
               {2, [:debug, :me]}
             ]
    end

    test "disable and enable collector" do
      start_supervised!(
        {TelemetryServer, server: name = unique_debug_name(), events: [[:debug, :me]]}
      )

      {:ok, collector_pid} = TelemetryServer.listen(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      :ok = TelemetryServer.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 2}, %{})
      :ok = TelemetryServer.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 3}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, :me]},
               {3, [:debug, :me]}
             ]

      Process.exit(collector_pid, :normal)
    end

    test "disable and enable are idempotent" do
      start_supervised!(
        {TelemetryServer, server: name = unique_debug_name(), events: [[:debug, :me]]}
      )

      {:ok, collector_pid} = TelemetryServer.listen(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      :ok = TelemetryServer.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = TelemetryServer.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 2}, %{})
      :ok = TelemetryServer.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = TelemetryServer.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 3}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, :me]},
               {3, [:debug, :me]}
             ]

      Process.exit(collector_pid, :normal)
    end
  end

  defp reduce_events(collector_pid) do
    PhoenixProfiler.TelemetryCollector.reduce(collector_pid, [], fn
      {:telemetry, _, event, event_ts, _}, acc ->
        acc ++ [{event_ts, event}]
    end)
  end

  defp unique_debug_name, do: :"profiler_#{System.unique_integer([:positive, :monotonic])}"
end
