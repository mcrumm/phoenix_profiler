defmodule PhoenixProfiler.TelemetryRegistryTest do
  use ExUnit.Case
  alias PhoenixProfiler.TelemetryRegistry

  describe "register/4" do
    test "when a collector is already registered" do
      {:ok, _} = TelemetryRegistry.register(nil, self())

      assert TelemetryRegistry.register(nil, self()) == {:error, {:already_registered, self()}}

      test_pid = self()

      assert fn -> TelemetryRegistry.register(nil, test_pid) end |> Task.async() |> Task.await() ==
               {:error, {:already_registered, self()}}
    end

    test "collector is enabled by default" do
      assert {:ok, _pid} = TelemetryRegistry.register(nil, self(), nil)

      assert self() in Registry.keys(TelemetryRegistry, self())
      assert [{_pid, {nil, nil, :enable}}] = Registry.lookup(TelemetryRegistry, self())
    end

    test "disable on register" do
      assert {:ok, _pid} = TelemetryRegistry.register(nil, self(), nil, :disable)

      assert self() in Registry.keys(TelemetryRegistry, self())
      assert [{_pid, {nil, nil, :disable}}] = Registry.lookup(TelemetryRegistry, self())
    end
  end

  test "update_info/1" do
    assert {:ok, _} = TelemetryRegistry.register(nil, self(), nil, :enable)
    TelemetryRegistry.update_info(self(), fn :enable -> :disable end)
    assert [{_pid, {nil, nil, :disable}}] = Registry.lookup(TelemetryRegistry, self())

    TelemetryRegistry.update_info(self(), fn :disable -> :enable end)
    assert [{_pid, {nil, nil, :enable}}] = Registry.lookup(TelemetryRegistry, self())
  end
end
