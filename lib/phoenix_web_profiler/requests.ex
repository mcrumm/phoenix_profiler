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
      :telemetry.attach(
        __MODULE__,
        [:phoenix, :endpoint, :stop],
        &__MODULE__.handle_event/4,
        table
      )

    {:ok, table}
  end

  # Telemetry callback
  def handle_event([:phoenix, :endpoint, :stop], %{duration: duration}, %{conn: conn}, table) do
    {token, profile} = Request.profile_request(conn)

    :ets.insert(table, {token, Map.put(profile, :duration, duration)})
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
end
