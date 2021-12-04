defmodule PhoenixProfiler.DashboardTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  alias PhoenixProfilerTest.Endpoint
  alias PhoenixProfilerWeb.Request

  @endpoint Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "puts profiler header on the response when enabled", %{conn: conn} do
    conn = get(conn, "/")

    assert [token] = Plug.Conn.get_resp_header(conn, Request.token_header_key())
    assert [url] = Plug.Conn.get_resp_header(conn, Request.profiler_header_key())

    assert url == "http://localhost:4000/dashboard/_profiler?nav=requests&token=#{token}"
  end
end
