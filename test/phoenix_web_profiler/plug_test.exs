defmodule PhoenixProfiler.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias PhoenixProfilerWeb.Request

  doctest PhoenixProfiler

  test "keys" do
    assert Request.token_key() == :pwdt
    assert Request.token_header_key() == "x-debug-token"
  end

  defp conn(path) do
    :get
    |> conn(path)
    |> Plug.Conn.put_private(:phoenix_endpoint, PhoenixProfilerTest.Endpoint)
  end

  test "injects debug token header if configured" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "")

    token = Request.debug_token!(conn)

    assert get_resp_header(conn, Request.token_header_key()) == [token]
  end

  test "skips debug token when disabled at the Endpoint" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixProfilerTest.EndpointDisabled)
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "")

    assert get_resp_header(conn, Request.token_header_key()) == []
  end

  test "injects debug toolbar for html requests if configured and contains the <body> tag" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_resp_content_type("text/html")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "<html><body><h1>PhoenixProfiler</h1></body></html>")

    token = Request.debug_token!(conn)

    assert to_string(conn.resp_body) =~
             ~s[<html><body><h1>PhoenixProfiler</h1><div id="pwdt#{token}" class="phxprof-toolbar" role="region" name="Phoenix Web Debug Toolbar">]
  end

  test "skips debug toolbar injection when disabled at the Endpoint" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixProfilerTest.EndpointDisabled)
      |> put_resp_content_type("text/html")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "<html><body><h1>PhoenixProfiler</h1></body></html>")

    assert get_resp_header(conn, Request.token_header_key()) == []

    assert to_string(conn.resp_body) == "<html><body><h1>PhoenixProfiler</h1></body></html>"
  end

  test "skips toolbar injection if html response is missing the body tag" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_resp_content_type("text/html")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "<h1>PhoenixProfiler</h1>")

    assert to_string(conn.resp_body) == "<h1>PhoenixProfiler</h1>"
  end

  test "skips toolbar injection if not an html request" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_resp_content_type("application/json")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "")

    token = Request.debug_token!(conn)

    refute to_string(conn.resp_body) =~
             ~s(<div id="pwdt#{token}")
  end
end
