defmodule PhoenixWeb.Profiler.TokenTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  alias PhoenixWeb.ProfilerTest.Endpoint

  @endpoint Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "sets debug token for browser requests", %{conn: conn} do
    conn = get(conn, "/")

    assert [_token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
  end

  test "sets debug token for api requests", %{conn: conn} do
    conn = get(conn, "/api")

    assert [_token] = Plug.Conn.get_resp_header(conn, "x-debug-token")
  end
end
