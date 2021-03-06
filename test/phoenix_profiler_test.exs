defmodule PhoenixProfilerUnitTest do
  use ExUnit.Case, async: true
  alias Phoenix.LiveView.Socket
  alias PhoenixProfiler.Profile

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

  defp build_conn(endpoint) do
    build_conn()
    |> PhoenixProfiler.Utils.put_private(:phoenix_endpoint, endpoint)
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

  describe "enable/1 with Plug.Conn" do
    test "raises when the profiler is not defined on the endpoint" do
      assert_raise RuntimeError,
                   ~r/attempted to enable profiling but no profiler is configured on the endpoint/,
                   fn ->
                     NoConfigEndpoint
                     |> build_conn()
                     |> PhoenixProfiler.enable()
                   end
    end

    test "raises when the profiler is not running" do
      assert_raise RuntimeError,
                   ~r/attempted to enable profiling but the profiler is not running/,
                   fn ->
                     EndpointMock
                     |> build_conn()
                     |> PhoenixProfiler.enable()
                   end
    end

    test "puts a profile on the conn" do
      start_supervised!({PhoenixProfiler, name: MyProfiler})

      conn =
        build_conn()
        |> PhoenixProfiler.Utils.put_private(:phoenix_endpoint, EndpointMock)
        |> PhoenixProfiler.enable()

      %Profile{server: MyProfiler, info: :enable} = conn.private.phoenix_profiler
    end
  end

  describe "enable/1 with LiveView.Socket" do
    test "raises when socket is not connected" do
      assert_raise RuntimeError,
                   ~r/attempted to enable profiling on a disconnected socket/,
                   fn ->
                     PhoenixProfiler.enable(build_socket())
                   end
    end

    test "raises when the profiler is not configured on the endpoint" do
      assert_raise RuntimeError,
                   ~r/attempted to enable profiling but no profiler is configured on the endpoint/,
                   fn ->
                     build_socket()
                     |> Map.put(:endpoint, NoConfigEndpoint)
                     |> connect()
                     |> PhoenixProfiler.enable()
                   end
    end

    test "raises when the profiler is not running" do
      assert_raise RuntimeError,
                   ~r/attempted to enable profiling but the profiler is not running/,
                   fn ->
                     build_socket() |> connect() |> PhoenixProfiler.enable()
                   end
    end

    test "puts a profile on the socket" do
      start_supervised!({PhoenixProfiler, name: MyProfiler})
      socket = build_socket() |> connect() |> PhoenixProfiler.enable()
      assert %Profile{server: MyProfiler, info: :enable} = socket.private.phoenix_profiler
    end
  end

  test "disable/1 when no profile is set" do
    conn = build_conn(EndpointMock)
    assert PhoenixProfiler.disable(conn) == conn

    socket = build_socket() |> connect() |> PhoenixProfiler.disable()
    assert PhoenixProfiler.disable(socket) == socket
  end

  test "disable/1 with Plug.Conn" do
    start_supervised!({PhoenixProfiler, name: MyProfiler})

    conn =
      build_conn()
      |> PhoenixProfiler.Utils.put_private(:phoenix_endpoint, EndpointMock)
      |> PhoenixProfiler.enable()

    assert conn.private.phoenix_profiler.info == :enable
    conn = PhoenixProfiler.disable(conn)
    assert conn.private.phoenix_profiler.info == :disable
  end

  test "disable/1 with LiveView.Socket" do
    start_supervised!({PhoenixProfiler, name: MyProfiler})
    socket = build_socket() |> connect() |> PhoenixProfiler.enable()
    assert socket.private.phoenix_profiler.info == :enable
    socket = PhoenixProfiler.disable(socket)
    assert socket.private.phoenix_profiler.info == :disable
  end
end
