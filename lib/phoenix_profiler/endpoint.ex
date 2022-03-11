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

        case PhoenixProfiler.Profiler.preflight(__MODULE__) do
          {:ok, profile} ->
            try do
              conn
              |> PhoenixProfiler.Endpoint.__prologue__(profile)
              |> super(opts)
              |> PhoenixProfiler.Endpoint.__epilogue__(start_time)
            catch
              kind, reason ->
                stack = __STACKTRACE__
                PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, profile, start_time)
            end

          :error ->
            super(conn, opts)
        end
      end
    end
  end

  alias PhoenixProfiler.{Profile, Profiler}

  def __prologue__(conn, %Profile{} = profile) do
    {:ok, pid} = Profiler.start_collector(conn, profile)
    telemetry_execute(:start, %{system_time: System.system_time()}, %{conn: conn})

    conn
    |> Plug.Conn.put_private(:phoenix_profiler, profile)
    |> Plug.Conn.put_private(:phoenix_profiler_collector, pid)
  end

  def __epilogue__(conn, start_time) do
    profile = Map.fetch!(conn.private, :phoenix_profiler)
    telemetry_execute(:stop, %{duration: duration(start_time)}, %{conn: conn})
    late_collect(conn, profile)
  end

  def __epilogue__(conn, kind, reason, stack, profile, start_time) do
    telemetry_execute(:exception, %{duration: duration(start_time)}, %{
      conn: conn,
      profile: profile,
      kind: kind,
      reason: reason,
      stacktrace: stack
    })

    {_, pid} = PhoenixProfiler.Utils.collector_info(profile.server, conn)
    late_collect(conn, profile, pid)
  end

  def __catch__(conn, kind, reason, stack, profile, start_time) do
    __epilogue__(conn, kind, reason, stack, profile, start_time)
    :erlang.raise(kind, reason, stack)
  end

  defp telemetry_execute(action, measurements, metadata) do
    :telemetry.execute([:phoenix_profiler, :endpoint, action], measurements, metadata)
  end

  defp duration(start_time) when is_integer(start_time) do
    System.monotonic_time() - start_time
  end

  defp late_collect(conn, profile) do
    late_collect(conn, profile, conn.private.phoenix_profiler_collector)
  end

  defp late_collect(conn, profile, collector_pid) do
    case PhoenixProfiler.Profiler.collect(profile, collector_pid) do
      {:ok, profile} ->
        true = PhoenixProfiler.Profiler.insert_profile(profile)
        conn

      :error ->
        conn
    end
  end
end
