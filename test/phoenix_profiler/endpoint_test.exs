defmodule PhoenixProfiler.EndpointTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias __MODULE__.Profiler

  Application.put_env(:phoenix_profiler, __MODULE__.Endpoint,
    url: [host: "example.com"],
    server: false,
    http: [port: 80],
    https: [port: 443],
    phoenix_profiler: [server: Profiler]
  )

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :phoenix_profiler
    use PhoenixProfiler
  end

  Application.put_env(:phoenix_profiler, __MODULE__.NoProfilerServerEndpoint, phoenix_profiler: [])

  defmodule NoProfilerServerEndpoint do
    use Phoenix.Endpoint, otp_app: :phoenix_profiler
    use PhoenixProfiler
  end

  setup_all do
    start_supervised!({PhoenixProfiler, name: Profiler})
    ExUnit.CaptureLog.capture_log(fn -> start_supervised!(Endpoint) end)
    :ok
  end

  test "warns if there is no server on the profiler configuration" do
    start_supervised!(NoProfilerServerEndpoint)

    assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
             conn = conn(:get, "/")
             NoProfilerServerEndpoint.call(conn, [])
           end) =~ "no profiler server"
  end

  test "puts profiler info on conn" do
    conn = Endpoint.call(conn(:get, "/"), [])
    profile = conn.private.phoenix_profiler
    assert %PhoenixProfiler.Profile{} = profile
    assert conn.private.phoenix_profiler.server == Profiler
    assert conn.private.phoenix_profiler.info == :enable

    assert conn.private.phoenix_profiler.url ==
             "https://example.com/dashboard/_profiler?nav=#{inspect(Profiler)}&panel=request&token=#{profile.token}"

    assert is_pid(conn.private.phoenix_profiler_collector)
  end

  test "skips profiling live_reload frame" do
    for path <- ["/phoenix/live_reload/frame", "/phoenix/live_reload/frame/suffix"] do
      conn = Endpoint.call(conn(:get, path), [])
      refute Map.has_key?(conn.private, :phoenix_profiler)
      refute Map.has_key?(conn.private, :phoenix_profiler_collector)
    end
  end
end
