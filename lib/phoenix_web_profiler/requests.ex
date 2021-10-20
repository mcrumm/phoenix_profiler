defmodule PhoenixWeb.Profiler.Requests do
  @moduledoc false
  use GenServer

  @tab :phoenix_web_profiler_requests

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(arg) do
    :ets.new(@tab, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    {:ok, arg}
  end

  def get(token) do
    case :ets.lookup(@tab, token) do
      [] ->
        nil

      [{_token, value}] ->
        value
    end
  end

  def put(token, value), do: :ets.insert(@tab, {token, value})
end
