defmodule PhoenixProfiler.Profiler do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  alias PhoenixProfiler.Utils
  alias PhoenixProfilerWeb.Request

  defstruct [:tab]

  defmacro __using__(opts) do
    quote do
      @otp_app unquote(opts)[:otp_app]

      def child_spec(_) do
        %{
          id: __MODULE__,
          start: {PhoenixProfiler.Profiler, :start_link, [__MODULE__]}
        }
      end
    end
  end

  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: module)
  end

  def init(module) do
    tab = :ets.new(module, [:set, :public, {:write_concurrency, true}])
    :persistent_term.put({PhoenixProfiler, module}, %__MODULE__{tab: tab})

    :telemetry.attach_many(
      {PhoenixProfiler, module, self()},
      [
        [:phxprof, :plug, :start],
        [:phoenix, :endpoint, :stop],
        [:phxprof, :plug, :stop]
      ],
      &__MODULE__.telemetry_callback/4,
      {module, tab}
    )

    {:ok, %{profiler: module, requests: tab}}
  end

  def profiler(%Plug.Conn{} = conn), do: conn.private[:phxprof_profiler]

  def get(profiler, token) do
    case :ets.lookup(table(profiler), token) do
      [] ->
        nil

      [{_token, value}] ->
        value
    end
  end

  def list(profiler) do
    :ets.tab2list(table(profiler))
  end

  def list_advanced(profiler, _search, sort_by, sort_dir, _limit) do
    Utils.sort_by(list(profiler), fn {_, profile} -> profile[sort_by] end, sort_dir)
  end

  def remote_get(node, profiler, token) do
    :rpc.call(node, __MODULE__, :get, [profiler, token])
  end

  def remote_list_advanced(node, profiler, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :list_advanced, [profiler, search, sort_by, sort_dir, limit])
  end

  defp table(profiler) do
    %__MODULE__{tab: tab} = :persistent_term.get({PhoenixProfiler, profiler})
    tab
  end

  def telemetry_callback([:phxprof, :plug, :start], measurements, _meta, _context) do
    Process.put(:phxprof_profiler_time, measurements.system_time)
  end

  def telemetry_callback([:phoenix, :endpoint, :stop], %{duration: duration}, _meta, _context) do
    Process.put(:phxprof_endpoint_duration, duration)
  end

  def telemetry_callback(
        [:phxprof, :plug, :stop],
        %{duration: duration},
        %{conn: %{private: %{phxprof_profiler: profiler}} = conn},
        {profiler, table}
      ) do
    {token, profile} = Request.profile_request(conn)

    profile = put_in(profile, [:metrics, :total_duration], duration)

    :ets.insert(table, {token, profile})
  end

  def telemetry_callback([:phxprof, :plug, :stop], _, _, _), do: :ok
end
