defmodule PhoenixProfiler.ServerTest do
  use ExUnit.Case
  alias PhoenixProfiler.Server
  doctest Server

  describe "subscribe/1" do
    test "returns :error when no owner is registered" do
      assert Server.subscribe(self()) == :error
    end

    test "returns {:ok, token} for a registered owner" do
      {:ok, token} = PhoenixProfiler.Server.put_owner_token()
      assert {:ok, ^token} = Server.subscribe(self())
    end

    test "sends telemetry for owner" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token()
      {:ok, token} = Server.subscribe(self())

      time = System.unique_integer()
      :ok = test_telemetry(time)

      assert_receive_telemetry(token, time)
    end

    test "receives telemetry for $callers" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token()
      {:ok, token} = Server.subscribe(self())

      inner_1 = System.unique_integer()
      inner_2 = System.unique_integer()

      Task.async(fn ->
        :ok = test_telemetry(inner_1)
        Task.async(fn -> test_telemetry(inner_2) end) |> Task.await()
      end)
      |> Task.await()

      assert_receive_telemetry(token, inner_1)
      assert_receive_telemetry(token, inner_2)
    end

    test "disable and enable collector" do
      start_supervised!({Server, server: name = unique_debug_name(), events: [[:debug, :me]]})

      {:ok, collector_pid} = Server.listen(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      :ok = Server.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 2}, %{})
      :ok = Server.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 3}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, :me]},
               {3, [:debug, :me]}
             ]

      Process.exit(collector_pid, :normal)
    end

    test "disable and enable are idempotent" do
      start_supervised!({Server, server: name = unique_debug_name(), events: [[:debug, :me]]})

      {:ok, collector_pid} = Server.listen(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      :ok = Server.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = Server.collector_info_exec(:disable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 2}, %{})
      :ok = Server.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = Server.collector_info_exec(:enable)
      :timer.sleep(1)
      :ok = :telemetry.execute([:debug, :me], %{system_time: 3}, %{})

      assert reduce_events(collector_pid) == [
               {1, [:debug, :me]},
               {3, [:debug, :me]}
             ]

      Process.exit(collector_pid, :normal)
    end
  end

  @test_telemetry_event [:phoenix_profiler, :internal, :this_is_only_used_for_testing]

  defp test_telemetry(time) do
    :telemetry.execute(@test_telemetry_event, %{system_time: time}, %{})
  end

  defp assert_receive_telemetry(token, time) do
    assert_receive {PhoenixProfiler.Server, ^token,
                    {:telemetry, @test_telemetry_event, ^time, nil}}
  end

  defp reduce_events(collector_pid) do
    PhoenixProfiler.TelemetryCollector.reduce(collector_pid, [], fn
      {:telemetry, _, event, event_ts, _}, acc ->
        acc ++ [{event_ts, event}]
    end)
  end

  defp unique_debug_name, do: :"profiler_#{System.unique_integer([:positive, :monotonic])}"
end
