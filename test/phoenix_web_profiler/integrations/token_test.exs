defmodule PhoenixWeb.Profiler.TokenTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  alias PhoenixWeb.ProfilerTest.{Endpoint, Router}

  @endpoint Endpoint

  setup do
    conn =
      Phoenix.ConnTest.build_conn(:get, "http://www.example.com/", nil)
      |> Phoenix.ConnTest.bypass_through(Router, [:browser])
      |> get("/")

    {:ok, conn: conn}
  end

  test "sets debug token", %{conn: conn} do
    {:ok, conn} = get(conn, "/")

    assert [_token | []] = Plug.Conn.get_resp_header(conn, "x-debug-token")
  end
end
