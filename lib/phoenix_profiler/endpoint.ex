defmodule PhoenixProfiler.Endpoint do
  # Overrides Phoenix.Endpoint.call/2 for profiling.
  @moduledoc false

  defmacro __before_compile__(%{module: _module}) do
    quote do
      defoverridable call: 2

      # Ignore requests from :phoenix_live_reload
      def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, opts) do
        super(conn, opts)
      end

      def call(conn, opts) do
        start_time = System.monotonic_time()
        endpoint = __MODULE__
        config = endpoint.config(:phoenix_profiler)
        conn = PhoenixProfiler.Endpoint.__prologue__(conn, endpoint, config)

        try do
          conn
          |> super(opts)
          |> PhoenixProfiler.Endpoint.__epilogue__(start_time)
        catch
          kind, reason ->
            stack = __STACKTRACE__
            PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, config, start_time)
        end
      end
    end
  end

  # Skip profiling if no configuration set on the Endpoint
  def __prologue__(conn, _endpoint, nil) do
    conn
  end

  def __prologue__(conn, endpoint, config) do
    if server = config[:server] do
      conn = PhoenixProfiler.Profiler.apply_configuration(conn, endpoint, server, config)
      telemetry_execute(:start, %{system_time: System.system_time()}, %{conn: conn})
      conn
    else
      IO.warn("no profiler server found for endpoint #{inspect(endpoint)}")
      conn
    end
  end

  def __catch__(conn, kind, reason, stack, config, start_time) do
    __epilogue__(conn, kind, reason, stack, config, start_time)
    :erlang.raise(kind, reason, stack)
  end

  def __epilogue__(conn, start_time) do
    if profiler = conn.private[:phoenix_profiler] do
      telemetry_execute(:stop, %{duration: duration(start_time)}, %{
        conn: conn,
        profiler: profiler
      })

      late_collect(conn)
    else
      conn
    end
  end

  def __epilogue__(conn, kind, reason, stack, _config, start_time) do
    if profiler = conn.private[:phoenix_profiler] do
      telemetry_execute(:exception, %{duration: duration(start_time)}, %{
        conn: conn,
        profiler: profiler,
        kind: kind,
        reason: reason,
        stacktrace: stack
      })

      late_collect(conn, {kind, reason, stack})
    end
  end

  defp telemetry_execute(action, measurements, metadata) do
    :telemetry.execute([:phoenix_profiler, :endpoint, action], measurements, metadata)
  end

  defp duration(start_time) when is_integer(start_time) do
    System.monotonic_time() - start_time
  end

  defp late_collect(conn, _error \\ nil) do
    case PhoenixProfiler.Profiler.collect(conn) do
      {:ok, profile} ->
        true = PhoenixProfiler.Profiler.insert_profile(profile)
        conn

      :error ->
        conn
    end
  end
end
