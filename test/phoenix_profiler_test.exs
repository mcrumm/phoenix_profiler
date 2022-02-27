defmodule PhoenixProfilerUnitTest do
  use ExUnit.Case, async: true
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

  describe "configure/1 with Plug.Conn" do
    test "returns {:error, :profiler_not_available} when the profiler is not defined on the endpoint" do
      assert NoConfigEndpoint
             |> build_conn()
             |> PhoenixProfiler.Profiler.configure() == {:error, :profiler_not_available}
    end

    test "raises when the profiler is not running" do
      assert_raise RuntimeError,
                   ~r/attempted to configure a profiler on the given conn, but the profiler is not running/,
                   fn ->
                     EndpointMock
                     |> build_conn()
                     |> PhoenixProfiler.Profiler.configure()
                   end
    end

    test "starts a collector" do
      profiler_name = MyProfiler
      start_supervised!({PhoenixProfiler, name: profiler_name})

      conn = build_conn()

      assert PhoenixProfiler.Utils.collector_info(profiler_name, conn) == :error

      assert {:ok, conn} =
               conn
               |> PhoenixProfiler.Utils.put_private(:phoenix_endpoint, EndpointMock)
               |> PhoenixProfiler.Profiler.configure()

      assert {:enable, collector_pid} = PhoenixProfiler.Utils.collector_info(profiler_name, conn)

      assert Process.alive?(collector_pid)
    end
  end

  describe "configure/1 with LiveView.Socket" do
    test "raises when socket is not connected" do
      assert_raise RuntimeError,
                   ~r/attempted to configure a profiler on the given socket, but it is disconnected/,
                   fn ->
                     PhoenixProfiler.Profiler.configure(build_socket())
                   end
    end

    test "returns {:error, :profiler_not_available} when the profiler is not defined on the endpoint" do
      assert build_socket()
             |> Map.put(:endpoint, NoConfigEndpoint)
             |> connect()
             |> PhoenixProfiler.Profiler.configure() == {:error, :profiler_not_available}
    end

    test "raises when the profiler is not running" do
      assert_raise RuntimeError,
                   ~r/attempted to configure a profiler on the given socket, but the profiler is not running/,
                   fn ->
                     build_socket() |> connect() |> PhoenixProfiler.Profiler.configure()
                   end
    end

    test "does not start a collector" do
      profiler_name = MyProfiler
      start_supervised!({PhoenixProfiler, name: profiler_name})
      socket = build_socket() |> connect()

      assert PhoenixProfiler.Utils.collector_info(profiler_name, socket) == :error

      assert {:ok, socket} = PhoenixProfiler.Profiler.configure(socket)

      assert PhoenixProfiler.Utils.collector_info(profiler_name, socket) == :error
    end
  end

  test "disable/1 with Plug.Conn" do
    profiler = start_profiler!()

    conn =
      build_conn()
      |> PhoenixProfiler.Utils.put_private(:phoenix_endpoint, EndpointMock)

    assert PhoenixProfiler.Utils.collector_info(profiler, conn) == :error

    {:ok, conn} = PhoenixProfiler.Profiler.configure(conn)
    assert {:enable, _pid} = PhoenixProfiler.Utils.collector_info(profiler, conn)

    conn = PhoenixProfiler.disable(conn)
    assert conn.private.phoenix_profiler_info == :disable
  end

  test "disable/1 with LiveView.Socket" do
    profiler = start_profiler!()

    socket = build_socket() |> connect()
    assert PhoenixProfiler.Utils.collector_info(profiler, socket) == :error

    {:ok, socket} = PhoenixProfiler.Profiler.configure(socket)

    {:ok, pid} =
      PhoenixProfiler.TelemetryServer.listen(
        profiler,
        PhoenixProfiler.Utils.transport_pid(socket)
      )

    assert {:enable, ^pid} = PhoenixProfiler.Utils.collector_info(profiler, socket)

    socket = PhoenixProfiler.disable(socket)
    assert socket.private.phoenix_profiler_info == :disable

    :timer.sleep(10)
    assert {:disable, ^pid} = PhoenixProfiler.Utils.collector_info(profiler, socket)
  end

  defp start_profiler!(name \\ MyProfiler) do
    start_supervised!({PhoenixProfiler, name: name})
    name
  end
end
