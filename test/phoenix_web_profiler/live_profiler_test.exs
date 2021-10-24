defmodule PhoenixWeb.LiveProfilerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias PhoenixWeb.Profiler.Session

  defp conn(path) do
    :get
    |> conn(path)
    |> init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, PhoenixWeb.ProfilerTest.Endpoint)
  end

  defp profiler(conn, opts \\ []) do
    PhoenixWeb.Profiler.call(conn, PhoenixWeb.Profiler.init(opts))
  end

  test "raises if Profiler plug was not called first" do
    opts = PhoenixWeb.LiveProfiler.init([])
    conn = conn("/")

    assert_raise RuntimeError, fn ->
      PhoenixWeb.LiveProfiler.call(conn, opts)
    end
  end

  test "injects debug session token if configured" do
    opts = PhoenixWeb.LiveProfiler.init([])

    conn =
      conn("/")
      |> profiler()
      |> PhoenixWeb.LiveProfiler.call(opts)
      |> send_resp(200, "")

    assert Session.session_token!(conn)
  end

  test "skips injecting session token if disabled at the Endpoint" do
    opts = PhoenixWeb.LiveProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixWeb.ProfilerTest.EndpointDisabled)
      |> profiler()
      |> PhoenixWeb.LiveProfiler.call(opts)
      |> send_resp(200, "")

    assert_raise RuntimeError, "session token not set", fn ->
      Session.session_token!(conn)
    end
  end
end
