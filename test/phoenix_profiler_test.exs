defmodule PhoenixProfilerUnitTest do
  use ExUnit.Case, async: true
  alias Phoenix.LiveView.Socket

  defp build_socket(view \\ TestLive) do
    %Socket{view: view}
  end

  defp connect(%Socket{} = socket) do
    %{socket | transport_pid: self()}
  end

  describe "enable_live_profiler/1" do
    test "raises when socket is not connected" do
      assert_raise RuntimeError,
                   ~r/attempted to enable live profiling on a disconnected socket/,
                   fn ->
                     PhoenixProfiler.enable_live_profiler(build_socket())
                   end
    end

    test "puts a profile key on socket.private.phxprof_enabled" do
      socket = build_socket() |> connect() |> PhoenixProfiler.enable_live_profiler()
      assert {TestLive, ref} = socket.private.phxprof_enabled
      assert is_reference(ref)
    end
  end

  test "disable_live_profiler/1 puts false for the profile key" do
    socket = build_socket() |> connect() |> PhoenixProfiler.enable_live_profiler()
    assert socket.private.phxprof_enabled
    socket = PhoenixProfiler.disable_live_profiler(socket)
    assert socket.private.phxprof_enabled == false
  end
end
