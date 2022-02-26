defmodule PhoenixProfiler.PhoenixProfilerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfilerTest.Endpoint

  @endpoint Endpoint

  @token_header_key "x-debug-token"
  @profiler_header_key "x-debug-token-link"

  setup do
    {:ok, conn: build_conn()}
  end

  test "profiling a browser request", %{conn: conn} do
    conn = get(conn, "/")

    assert [token] = Plug.Conn.get_resp_header(conn, @token_header_key)
    assert [url] = Plug.Conn.get_resp_header(conn, @profiler_header_key)

    assert url ==
             "http://localhost:4000/dashboard/_profiler?nav=PhoenixProfilerTest.Profiler&panel=request&token=#{token}"

    %Profile{
      data: %{
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
      }
    } = conn |> ProfileStore.profiler() |> ProfileStore.get(token)

    assert metrics.total_duration > 0
    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end

  test "profiling through a forwarded plug", %{conn: conn} do
    conn = get(conn, "/plug-router")
    assert [token] = Plug.Conn.get_resp_header(conn, @token_header_key)
    assert [_] = Plug.Conn.get_resp_header(conn, @profiler_header_key)
    assert conn |> ProfileStore.profiler() |> ProfileStore.get(token)
  end

  test "profiling an api request", %{conn: conn} do
    conn = get(conn, "/api")

    assert [token] = Plug.Conn.get_resp_header(conn, @token_header_key)
    assert [url] = Plug.Conn.get_resp_header(conn, @profiler_header_key)

    assert url ==
             "http://localhost:4000/dashboard/_profiler?nav=PhoenixProfilerTest.Profiler&panel=request&token=#{token}"

    %Profile{
      data: %{
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
      }
    } = conn |> ProfileStore.profiler() |> ProfileStore.get(token)

    assert metrics.endpoint_duration > 0
    assert metrics.memory > 0
  end

  test "when disabled in the pipeline", %{conn: conn} do
    conn = get(conn, "/disabled")

    assert Plug.Conn.get_resp_header(conn, @token_header_key) == []
    assert Plug.Conn.get_resp_header(conn, @profiler_header_key) == []
  end
end
