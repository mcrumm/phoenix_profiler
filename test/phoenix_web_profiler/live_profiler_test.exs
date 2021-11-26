defmodule PhoenixWeb.LiveProfilerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

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

  test "injects debug token into the session if configured" do
    opts = PhoenixWeb.LiveProfiler.init([])

    conn =
      conn("/")
      |> profiler()
      |> PhoenixWeb.LiveProfiler.call(opts)
      |> send_resp(200, "")

    assert %{"pwdt" => token} = Plug.Conn.get_session(conn)
    assert is_binary(token) and token != ""
  end

  test "skips injecting debug token into the session if disabled at the Endpoint" do
    opts = PhoenixWeb.LiveProfiler.init([])

    conn =
      conn("/")
      |> put_private(:phoenix_endpoint, PhoenixWeb.ProfilerTest.EndpointDisabled)
      |> profiler()
      |> PhoenixWeb.LiveProfiler.call(opts)
      |> send_resp(200, "")

    assert Plug.Conn.get_session(conn) == %{}
  end
end
