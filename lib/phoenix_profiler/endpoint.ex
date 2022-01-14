defmodule PhoenixProfiler.Endpoint do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      unquote(plug())

      @before_compile PhoenixProfiler.Endpoint
    end
  end

  defp plug do
    # todo: ensure we are within a Phoenix.Endpoint
    quote location: :keep do
      plug PhoenixProfiler.Plug
    end
  end

  @doc false
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
            PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, config, start_time)
        catch
          kind, reason ->
            stack = __STACKTRACE__
            PhoenixProfiler.Endpoint.__catch__(conn, kind, reason, stack, config, start_time)
        end
      end
    end
  end

  def __prologue__(conn, endpoint) do
    config = endpoint.config(:phoenix_profiler)

    if config do
      conn = PhoenixProfiler.Utils.configure_profile(conn, endpoint, config, System.system_time())
      telemetry_execute(:start, %{system_time: System.system_time()}, %{conn: conn})
      conn
    else
      conn
    end
  end

  @doc false
  def __catch__(conn, kind, reason, stack, config, start_time) do
    __epilogue__(conn, kind, reason, stack, config, start_time)
    :erlang.raise(kind, reason, stack)
  end

  @doc false
  # todo: this should be all be handled in telemetry events (aka not special))
  #  - late collect (this can be its *own* telemetry event)
  #  - compile/persist the profile (built-in data collector than runs last?)
  def __epilogue__(conn, start_time) do
    if profile = conn.private[:phoenix_profiler] do
      telemetry_execute(:stop, %{duration: duration(start_time)}, %{
        conn: conn,
        profile: profile
      })

      conn
    else
      conn
    end
  end

  def __epilogue__(conn, start_time, kind, reason, stack, _config) do
    if profile = conn.private[:phoenix_profiler] do
      telemetry_execute(:exception, %{duration: duration(start_time)}, %{
        conn: conn,
        profile: profile,
        kind: kind,
        reason: reason,
        stacktrace: stack
      })
    end
  end

  defp telemetry_execute(action, measurements, metadata) do
    :telemetry.execute([:phoenix_profiler, :endpoint, action], measurements, metadata)
  end

  defp duration(start_time) when is_integer(start_time) do
    System.monotonic_time() - start_time
  end
end
