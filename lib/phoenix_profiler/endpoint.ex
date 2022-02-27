defmodule PhoenixProfiler.Endpoint do
  # Overrides Phoenix.Endpoint.call/2 for profiling.
  @moduledoc false

  defmacro __before_compile__(%{module: _module}) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        start_time = System.monotonic_time()

        try do
          conn
          |> PhoenixProfiler.Endpoint.__prologue__(__MODULE__)
          |> super(opts)
          |> PhoenixProfiler.Endpoint.__epilogue__(start_time)
        rescue
          # todo: rescue any profiler errors and handle them appropriately.
          e in Plug.Conn.WrapperError ->
            %{conn: conn, kind: kind, reason: reason, stack: stack} = e
            PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, start_time)
        catch
          kind, reason ->
            stack = __STACKTRACE__
            PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, start_time)
        end
      end
    end
  end

  # TODO: remove this clause when we add config for profiler exclude_patterns
  def __prologue__(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, _) do
    conn
  end

  def __prologue__(conn, endpoint) do
    case PhoenixProfiler.Profiler.configure(conn, endpoint) do
      {:ok, conn} ->
        telemetry_execute(:start, %{system_time: System.system_time()}, %{conn: conn})
        conn

      {:error, :profiler_not_available} ->
        conn
    end
  end

  def __catch__(conn, kind, reason, stack, start_time) do
    __epilogue__(conn, start_time, kind, reason, stack)
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

  def __epilogue__(conn, start_time, kind, reason, stack) do
    if profiler = conn.private[:phoenix_profiler] do
      telemetry_execute(:exception, %{duration: duration(start_time)}, %{
        conn: conn,
        profiler: profiler,
        kind: kind,
        reason: reason,
        stacktrace: stack
      })

      late_collect(conn, {kind, stack, reason})
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
