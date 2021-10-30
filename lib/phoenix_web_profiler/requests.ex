defmodule PhoenixWeb.Profiler.Requests do
  # Records request metadata from telemetry.
  @moduledoc false
  use GenServer
  alias PhoenixWeb.Profiler.Request

  @tab :phoenix_web_profiler_requests

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(_arg) do
    table =
      :ets.new(@tab, [
        :set,
        :public,
        {:write_concurrency, true}
      ])

    :ok =
      :telemetry.attach_many(
        __MODULE__,
        [
          [:phxweb, :profiler, :start],
          [:phoenix, :endpoint, :stop],
          [:phxweb, :profiler, :stop]
        ],
        &__MODULE__.handle_event/4,
        table
      )

    {:ok, table}
  end

  # Telemetry callback
  def handle_event([:phxweb, :profiler, :start], _measurements, _meta, _table) do
    # no-op
  end

  def handle_event([:phoenix, :endpoint, :stop], %{duration: duration}, meta, table) do
    %{conn: conn} = meta
    update_metrics(conn, table, :endpoint_duration, duration)
  end

  def handle_event([:phxweb, :profiler, :stop], %{duration: duration}, meta, table) do
    %{conn: conn} = meta
    update_metrics(conn, table, :total_duration, duration)
  end

  @impl GenServer
  def handle_call({:whereis, token}, _from, table) do
    {:reply, get(table, token), table}
  end

  def multi_get(token) do
    {replies, _} = GenServer.multi_call(__MODULE__, {:whereis, token})

    for {_node, reply} when not is_nil(reply) <- replies do
      reply
    end
  end

  def get(table, token) do
    case :ets.lookup(table, token) do
      [] ->
        nil

      [{_token, value}] ->
        value
    end
  end

  # Extract current conn profile, merge with existing metrics stored in ETS,
  # and put new values received on telemetry events.
  defp update_metrics(conn, table, key, duration) do
    {token, %{metrics: conn_metrics} = profile} = Request.profile_request(conn)

    metrics =
      case get(table, token) do
        %{metrics: metrics} -> metrics
        _ -> %{}
      end
      |> Map.merge(conn_metrics)
      |> Map.put(key, duration)

    profile = %{profile | metrics: metrics}
    :ets.insert(table, {token, profile})
  end
end
