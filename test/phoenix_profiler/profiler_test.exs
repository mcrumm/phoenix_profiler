defmodule PhoenixProfiler.ProfilerTest do
  use ExUnit.Case, async: true

  defmodule MyProfiler do
    use PhoenixProfiler, otp_app: :phoenix_profiler
  end

  describe "reset/0" do
    test "deletes all records in the table" do
      start_supervised!(MyProfiler)
      %PhoenixProfiler.Profiler{tab: tab} = :persistent_term.get({PhoenixProfiler, MyProfiler})

      :ets.insert(tab, {1, 1})
      :ets.insert(tab, {2, 1})
      :ets.insert(tab, {3, 1})

      MyProfiler.reset()

      assert :ets.tab2list(tab) == []
    end
  end

  describe "sweeping requests" do
    test "custom sweep interval" do
      start_supervised!({MyProfiler, request_sweep_interval: 0})
      %PhoenixProfiler.Profiler{tab: tab} = :persistent_term.get({PhoenixProfiler, MyProfiler})

      :ets.insert(tab, {"a", %{}})
      :ets.insert(tab, {"b", %{}})
      :ets.insert(tab, {"c", %{}})
      :ets.insert(tab, {"d", %{}})

      :timer.sleep(100)

      assert :ets.tab2list(tab) == []
    end
  end
end
