defmodule PhoenixWeb.Profiler.Transports do
  # Node-local storage for socket lookup by transport pid
  @moduledoc false
  use GenServer
  alias Phoenix.LiveView.Socket

  ## Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def delete(%Socket{transport_pid: pid} = socket) when is_pid(pid) do
    delete_socket(pid)
    socket
  end

  def get(%Socket{transport_pid: pid}) when is_pid(pid) do
    lookup(pid)
  end

  def put(%Socket{transport_pid: pid} = socket) when is_pid(pid) do
    put_socket(socket)
    socket
  end

  def root?(%Socket{root_pid: root_pid}) do
    root_pid == self()
  end

  ## Server API

  @tab :phoenix_web_profiler_sockets

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

  ## Private

  defp delete_socket(pid) do
    :ets.delete(@tab, pid)
  end

  defp lookup(key) do
    case :ets.lookup(@tab, key) do
      [] ->
        nil

      [{_key, value}] ->
        value
    end
  end

  defp put_socket(socket) do
    :ets.insert(
      @tab,
      {socket.transport_pid,
       %{
         root_pid: socket.root_pid,
         root_view: root_view(socket),
         live_action: socket.assigns.live_action
       }}
    )
  end

  defp root_view(socket) do
    if Map.has_key?(socket, :root_view) do
      socket.root_view
    else
      socket.private[:root_view]
    end
  end
end
