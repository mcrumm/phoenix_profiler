defmodule PhoenixProfiler.Requests do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  use GenServer

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    tab = :ets.new(__MODULE__, [:set, :public, :named_table, {:write_concurrency, true}])

    :persistent_term.put(__MODULE__, tab)

    :telemetry.attach_many(
      {__MODULE__, tab},
      [
        [:phxweb, :profiler, :start],
        [:phoenix, :endpoint, :stop],
        [:phxweb, :profiler, :stop]
      ],
      &__MODULE__.telemetry_callback/4,
      tab
    )

    {:ok, tab}
  end

  def get(token) do
    get(:persistent_term.get(__MODULE__), token)
  end

  def get(table, token) do
    case :ets.lookup(table, token) do
      [] ->
        nil

      [{_token, value}] ->
        value
    end
  end

  def remote_get(node, token) do
    :rpc.call(node, __MODULE__, :get, [token])
  end

  def telemetry_callback([:phxweb, :profiler, :start], _measurements, _meta, _table) do
    # no-op
  end

  def telemetry_callback([:phoenix, :endpoint, :stop], %{duration: duration}, _meta, _table) do
    Process.put(:phxweb_endpoint_duration, duration)
  end

  def telemetry_callback([:phxweb, :profiler, :stop], %{duration: duration}, %{conn: conn}, table) do
    {token, profile} = PhoenixWeb.Profiler.Request.profile_request(conn)

    profile = put_in(profile, [:metrics, :total_duration], duration)

    :ets.insert(table, {token, profile})
  end
end
