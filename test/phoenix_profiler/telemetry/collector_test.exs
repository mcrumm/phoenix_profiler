defmodule PhoenixProfiler.TelemetryCollectorTest do
  use ExUnit.Case
  alias PhoenixProfiler.TelemetryCollector
  alias PhoenixProfiler.TelemetryRegistry
  alias PhoenixProfiler.TelemetryServer

  doctest TelemetryCollector

  defmodule Collector do
    use GenServer

    def start_link(init_arg) do
      GenServer.start_link(__MODULE__, init_arg)
    end

    @impl true
    def init({server, pid}) do
      TelemetryRegistry.register(server, pid)
      {:ok, pid}
    end

    @impl true
    def handle_call({TelemetryCollector, :disable}, _from, pid) do
      TelemetryRegistry.update_info(pid, fn _ -> :disable end)
      {:reply, :ok, pid}
    end

    @impl true
    def handle_call({TelemetryCollector, :enable}, _from, pid) do
      TelemetryRegistry.update_info(pid, fn _ -> :enable end)
      {:reply, :ok, pid}
    end

    @impl true
    def handle_info({:telemetry, _, _, _, _} = event, pid) do
      send(pid, {:collector, event})
      {:noreply, pid}
    end
  end

  describe "collecting telemetry" do
    test "events from watched pid" do
      name = unique_debug_name()
      start_supervised!({PhoenixProfiler, name: name, telemetry: [[:debug, :me]]})

      {:ok, _} = TelemetryRegistry.register(name, self())

      :ok = :telemetry.execute([:debug, :me], %{}, %{})

      assert_received {:telemetry, _, [:debug, :me], _, _}
    end

    test "events from watched $callers" do
      name = unique_debug_name()
      start_supervised!({PhoenixProfiler, name: name, telemetry: [[:debug, :me]]})

      {:ok, _} = TelemetryRegistry.register(name, self())

      fn -> :telemetry.execute([:debug, :me], %{}, %{}) end
      |> Task.async()
      |> Task.await()

      assert_received {:telemetry, _, [:debug, :me], _, _}
    end

    test "events with custom arg" do
      name = unique_debug_name()
      start_supervised!({PhoenixProfiler, name: name, telemetry: [[:debug, :me]]})

      {:ok, _} = TelemetryRegistry.register(name, self(), :custom)

      :ok = :telemetry.execute([:debug, :me], %{}, %{})

      assert_received {:telemetry, :custom, [:debug, :me], _, _}
    end

    test "events with system_time measurements" do
      name = unique_debug_name()
      start_supervised!({PhoenixProfiler, name: name, telemetry: [[:debug, :me]]})

      {:ok, _} = TelemetryRegistry.register(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})

      assert_received {:telemetry, nil, [:debug, :me], 1, _}
    end

    test "when filter returns :keep, event data is an empty map" do
      name = unique_debug_name()

      start_supervised!(
        {PhoenixProfiler,
         name: name, telemetry: [[:debug, :me]], filter: fn _, _, _, _ -> :keep end}
      )

      {:ok, _} = TelemetryRegistry.register(name, self())

      :ok = :telemetry.execute([:debug, :me], %{}, %{})

      assert_received {:telemetry, nil, [:debug, :me], _, data}
                      when map_size(data) == 0
    end

    test "events when filter returns {:keep, data}, events are sent with custom data" do
      name = unique_debug_name()

      ref = make_ref()

      start_supervised!(
        {PhoenixProfiler.TelemetryServer,
         server: name, events: [[:debug, :me]], filter: fn _, _, _, _ -> {:keep, %{ref: ref}} end}
      )

      {:ok, _} = TelemetryRegistry.register(name, self())

      :ok = :telemetry.execute([:debug, :me], %{}, %{})

      assert_received {:telemetry, _, _, _, %{ref: ^ref}}
    end

    test "events with :skip filter" do
      name = unique_debug_name()

      keep_ref = make_ref()
      skip_ref = make_ref()

      start_supervised!(
        {PhoenixProfiler.TelemetryServer,
         server: name,
         events: [[:debug, :me]],
         filter: fn
           _, _, _, %{ref: ^keep_ref} = keep -> {:keep, keep}
           _, _, _, %{ref: ^skip_ref} -> :skip
         end}
      )

      {:ok, _} = TelemetryRegistry.register(name, self())

      :ok = :telemetry.execute([:debug, :me], %{}, %{ref: skip_ref})
      :ok = :telemetry.execute([:debug, :me], %{}, %{ref: keep_ref})

      assert_received {:telemetry, nil, [:debug, :me], _, %{ref: ^keep_ref}}
    end

    test "enabling and disabling a collector" do
      name = unique_debug_name()
      start_supervised!({PhoenixProfiler, name: name, telemetry: [[:debug, :me]]})

      start_supervised!({Collector, {name, self()}})

      :ok = :telemetry.execute([:debug, :me], %{system_time: 1}, %{})
      assert_receive {:collector, {:telemetry, nil, [:debug, :me], 1, _}}, 10

      :ok = TelemetryServer.disable_key(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 2}, %{})
      refute_receive {:collector, {:telemetry, nil, [:debug, :me], 2, _}}, 10

      :ok = TelemetryServer.enable_key(name, self())

      :ok = :telemetry.execute([:debug, :me], %{system_time: 3}, %{})
      assert_receive {:collector, {:telemetry, nil, [:debug, :me], 3, _}}, 10
    end
  end

  defp unique_debug_name do
    :"profiler_#{System.unique_integer([:positive, :monotonic])}"
  end
end
