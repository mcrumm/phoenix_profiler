defmodule PhoenixProfilerWeb.ProfilerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  alias PhoenixProfiler.Profiler
  alias PhoenixProfilerTest.Endpoint

  @endpoint Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "records a profile for browser requests", %{conn: conn} do
    conn = get(conn, "/")

    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
    assert profiler = Profiler.profiler(conn)

    %{
      conn: %Plug.Conn{
        host: "www.example.com",
        method: "GET",
        path_info: [],
        private: %{
          phoenix_action: :index,
          phoenix_controller: PhoenixProfilerTest.PageController,
          phoenix_endpoint: PhoenixProfilerTest.Endpoint,
          phoenix_router: PhoenixProfilerTest.Router,
          phoenix_view: PhoenixProfilerTest.PageView
        },
        status: 200
      },
      metrics: metrics
    } = Profiler.get(profiler, token)

    assert metrics.total_duration > 0
    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end

  test "records a profile through a forwarded plug", %{conn: conn} do
    conn = get(conn, "/plug-router")
    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
    assert profiler = Profiler.profiler(conn)
    assert Profiler.get(profiler, token)
  end

  test "records a profile for api requests", %{conn: conn} do
    conn = get(conn, "/api")

    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
    assert profiler = Profiler.profiler(conn)

    %{
      conn: %Plug.Conn{
        host: "www.example.com",
        method: "GET",
        path_info: ["api"],
        private: %{
          phoenix_action: :index,
          phoenix_controller: PhoenixProfilerTest.APIController,
          phoenix_endpoint: PhoenixProfilerTest.Endpoint,
          phoenix_router: PhoenixProfilerTest.Router,
          phoenix_view: PhoenixProfilerTest.APIView
        },
        status: 200
      },
      metrics: metrics
    } = Profiler.get(profiler, token)

    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end
end
