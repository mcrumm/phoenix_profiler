defmodule PhoenixWeb.Profiler.RequestsTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  alias PhoenixProfiler.Requests
  alias PhoenixWeb.ProfilerTest.Endpoint

  @endpoint Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "records debug profile for browser requests", %{conn: conn} do
    conn = get(conn, "/")

    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")

    %{
      conn: %Plug.Conn{
        host: "www.example.com",
        method: "GET",
        path_info: [],
        private: %{
          phoenix_action: :index,
          phoenix_controller: PhoenixWeb.ProfilerTest.PageController,
          phoenix_endpoint: PhoenixWeb.ProfilerTest.Endpoint,
          phoenix_router: PhoenixWeb.ProfilerTest.Router,
          phoenix_view: PhoenixWeb.ProfilerTest.PageView
        },
        status: 200
      },
      dumped: [],
      metrics: metrics
    } = Requests.get(token)

    assert metrics.total_duration > 0
    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end

  test "records debug profile through forwarded plug", %{conn: conn} do
    conn = get(conn, "/plug-router")
    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
    assert Requests.get(token)
  end

  test "records debug profile for api requests", %{conn: conn} do
    conn = get(conn, "/api")

    assert [token] = Plug.Conn.get_resp_header(conn, "x-debug-token")

    %{
      conn: %Plug.Conn{
        host: "www.example.com",
        method: "GET",
        path_info: ["api"],
        private: %{
          phoenix_action: :index,
          phoenix_controller: PhoenixWeb.ProfilerTest.APIController,
          phoenix_endpoint: PhoenixWeb.ProfilerTest.Endpoint,
          phoenix_router: PhoenixWeb.ProfilerTest.Router,
          phoenix_view: PhoenixWeb.ProfilerTest.APIView
        },
        status: 200
      },
      dumped: [],
      metrics: metrics
    } = Requests.get(token)

    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end
end
