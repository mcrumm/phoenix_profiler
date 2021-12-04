defmodule PhoenixProfiler.Requests do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  use GenServer
  alias PhoenixProfilerWeb.Request

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    unless Code.ensure_loaded?(:persistent_term) do
      require Logger
      Logger.error("PhoenixProfiler requires Erlang/OTP 21.3+")
      raise "PhoenixProfiler requires Erlang/OTP 21.3+"
    end

    tab = :ets.new(__MODULE__, [:set, :public, {:write_concurrency, true}])

    :persistent_term.put(__MODULE__, tab)

    :telemetry.attach_many(
      {__MODULE__, tab},
      [
        [:phxprof, :plug, :start],
        [:phoenix, :endpoint, :stop],
        [:phxprof, :plug, :stop]
      ],
      &__MODULE__.telemetry_callback/4,
      tab
    )

    {:ok, tab}
  end

  def get(token) do
    get(table(), token)
  end

  def get(table, token) do
    case :ets.lookup(table, token) do
      [] ->
        nil

      [{_token, value}] ->
        value
    end
  end

  def list do
    list(table())
  end

  def list(table) do
    :ets.tab2list(table)
  end

  def list_advanced(_search, _sort_by, _sort_dir, _limit) do
    list()
  end

  def remote_get(node, token) do
    :rpc.call(node, __MODULE__, :get, [token])
  end

  def remote_list_advanced(node, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :list_advanced, [search, sort_by, sort_dir, limit])
  end

  defp table do
    :persistent_term.get(__MODULE__)
  end

  def telemetry_callback([:phxprof, :plug, :start], measurements, _meta, _table) do
    Process.put(:phxprof_profiler_time, measurements.system_time)
  end

  def telemetry_callback([:phoenix, :endpoint, :stop], %{duration: duration}, _meta, _table) do
    Process.put(:phxprof_endpoint_duration, duration)
  end

  def telemetry_callback(
        [:phxprof, :plug, :stop],
        %{duration: duration},
        %{conn: conn},
        table
      ) do
    {token, profile} = Request.profile_request(conn)

    profile = put_in(profile, [:metrics, :total_duration], duration)

    :ets.insert(table, {token, profile})
  end
end
