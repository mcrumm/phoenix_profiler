defmodule PhoenixProfiler.ProfileStoreTest do
  use ExUnit.Case, async: false

  describe "reset/0" do
    test "deletes all records in the table" do
      tab = PhoenixProfiler.Server.Entry

      :ets.insert(tab, {1, 1})
      :ets.insert(tab, {2, 1})
      :ets.insert(tab, {3, 1})

      PhoenixProfiler.reset()

      assert :ets.tab2list(tab) == []
    end
  end

  describe "sweeping requests" do
    test "custom sweep interval" do
      tab = PhoenixProfiler.Server.Entry

      :ets.insert(tab, {"a", %{}})
      :ets.insert(tab, {"b", %{}})
      :ets.insert(tab, {"c", %{}})
      :ets.insert(tab, {"d", %{}})

      pid = Process.whereis(PhoenixProfiler.Server)
      send(pid, :sweep)
      :timer.sleep(100)

      assert :ets.tab2list(tab) == []
    end
  end
end
