defmodule PhoenixProfiler.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @token_header_key "x-debug-token"
  @profiler_header_key "x-debug-token-link"

  defp conn(path) do
    :get
    |> conn(path)
    |> put_private(:phoenix_endpoint, PhoenixProfilerTest.Endpoint)
  end

  test "injects debug token headers if configured" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "")

    assert [token] = Plug.Conn.get_resp_header(conn, @token_header_key)
    assert [url] = Plug.Conn.get_resp_header(conn, @profiler_header_key)

    assert url ==
             "http://localhost:4000/dashboard/_profiler?nav=PhoenixProfilerTest.Profiler&panel=request&token=#{token}"
  end

  test "skips debug token when disabled at the Endpoint" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixProfilerTest.EndpointDisabled)
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "")

    assert get_resp_header(conn, @token_header_key) == []
    assert get_resp_header(conn, @profiler_header_key) == []
  end

  test "injects debug toolbar for html requests if configured and contains the <body> tag" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_resp_content_type("text/html")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "<html><body><h1>PhoenixProfiler</h1></body></html>")

    assert [token] = get_resp_header(conn, @token_header_key)

    assert to_string(conn.resp_body) =~
             ~s[<html><body><h1>PhoenixProfiler</h1><!-- START Phoenix Web Debug Toolbar -->\n<div id="pwdt#{token}" class="phxprof-toolbar" role="region" name="Phoenix Web Debug Toolbar">]
  end

  test "skips debug toolbar injection when disabled at the Endpoint" do
    opts = PhoenixProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixProfilerTest.EndpointDisabled)
      |> put_resp_content_type("text/html")
      |> PhoenixProfiler.call(opts)
      |> send_resp(200, "<html><body><h1>PhoenixProfiler</h1></body></html>")

    assert get_resp_header(conn, @token_header_key) == []

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

    assert [token] = get_resp_header(conn, @token_header_key)

    refute to_string(conn.resp_body) =~
             ~s(<div id="pwdt#{token}")
  end
end
