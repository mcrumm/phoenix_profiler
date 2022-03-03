defmodule PhoenixProfilerUnitTest do
  use ExUnit.Case, async: true
  use ProfilerHelper
  alias Phoenix.LiveView.Socket

  doctest PhoenixProfiler

  defmodule EndpointMock do
    def config(:phoenix_profiler), do: [server: MyProfiler]
    def url, do: "http://endpoint:4000"
  end

  defmodule NoConfigEndpoint do
    def config(:phoenix_profiler), do: nil
    def url, do: "http://no-config-endpoint:4000"
  end

  defp build_conn do
    Plug.Test.conn(:get, "/")
  end

  defp build_socket(view \\ TestLive) do
    %Socket{endpoint: EndpointMock, view: view}
  end

  defp connect(%Socket{} = socket) do
    # TODO: replace with struct update when we require LiveView v0.15+.
    socket = Map.put(socket, :transport_pid, self())

    # TODO: remove when we require LiveView v0.15+.
    if Map.has_key?(socket, :connected?) do
      Map.put(socket, :connected?, true)
    else
      socket
    end
  end

  test "all_running/0" do
    start_supervised!({PhoenixProfiler, name: AllRunning_1})

    assert AllRunning_1 in PhoenixProfiler.all_running()

    start_supervised!({PhoenixProfiler, name: AllRunning_2})

    assert [AllRunning_1, AllRunning_2] -- PhoenixProfiler.all_running() == []
  end

  test "disable/1 with Plug.Conn" do
    profiler = start_profiler!()

    conn = build_conn()
    assert PhoenixProfiler.Utils.collector_info(profiler, conn) == :error

    conn = profile_thru(conn, EndpointMock)
    assert {:enable, _pid} = PhoenixProfiler.Utils.collector_info(profiler, conn)

    conn = PhoenixProfiler.disable(conn)
    assert conn.private.phoenix_profiler.info == :disable
  end

  test "disable/1 with LiveView.Socket" do
    profiler = start_profiler!()

    socket = build_socket() |> connect() |> PhoenixProfiler.Utils.maybe_mount_profiler()

    assert PhoenixProfiler.Utils.collector_info(profiler, socket) == :error

    {:ok, pid} =
      PhoenixProfiler.TelemetryServer.listen(
        profiler,
        PhoenixProfiler.Utils.transport_pid(socket)
      )

    assert {:enable, ^pid} = PhoenixProfiler.Utils.collector_info(profiler, socket)

    socket = PhoenixProfiler.disable(socket)
    assert socket.private.phoenix_profiler.info == :disable

    :timer.sleep(10)
    assert {:disable, ^pid} = PhoenixProfiler.Utils.collector_info(profiler, socket)
  end

  defp start_profiler!(name \\ MyProfiler) do
    start_supervised!({PhoenixProfiler, name: name})
    name
  end
end
