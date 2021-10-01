defmodule FriendsOfPhoenix.Debug.Server do
  # Debug server store info for the toolbar
  @moduledoc false
  use GenServer, restart: :temporary
  alias FriendsOfPhoenix.Debug

  @token_key Debug.token_key()

  ## Client

  def start_link(opts) do
    token = opts[:token] || raise "token is required to start the debug server"
    GenServer.start_link(__MODULE__, token, name: server_name(token))
  end

  def server_name(token) when is_binary(token) do
    Module.concat([Debug, Server, token])
  end

  def entries(token) do
    token |> server_name() |> Process.whereis() |> GenServer.call(:entries)
  end

  def put_entry(pid, namespace, info)
      when is_pid(pid) and is_atom(namespace) and is_map(info) do
    IO.inspect({namespace, info}, label: "Putting entry for #{inspect(pid)}")
    GenServer.call(pid, {:put_entry, namespace, info})
  end

  def put_entry(token, namespace, info)
      when is_binary(token) and is_atom(namespace) and is_map(info) do
    token |> server_name() |> Process.whereis() |> put_entry(namespace, info)
  end

  ## Server

  @impl GenServer
  def init(token) do
    :ok =
      :telemetry.attach(
        {Debug, token},
        [:fophx, :debug, :stop],
        &__MODULE__.__handle_event__/4,
        %{
          token: token
        }
      )

    {:ok, %{token: token, entries: %{}}}
  end

  @impl GenServer

  def handle_call({:put_entry, Debug = namespace, info}, _from, state) do
    :ok = :telemetry.detach({Debug, state.token})

    {:reply, :ok, %{state | entries: Map.put(state.entries, namespace, info)}}
  end

  def handle_call({:put_entry, namespace, info}, _from, state) do
    {:reply, :ok, %{state | entries: Map.put(state.entries, namespace, info)}}
  end

  @impl GenServer
  def handle_call(:entries, _from, state) do
    {:reply, state.entries, state}
  end

  ## Telemetry Handlers

  @doc false
  def __handle_event__(
        [:fophx, :debug, :stop],
        %{duration: duration},
        %{conn: %{private: %{@token_key => token}} = conn},
        %{token: token}
      ) do
    infos =
      conn.private
      |> Map.take([
        :phoenix_action,
        :phoenix_controller,
        :phoenix_endpoint,
        :phoenix_router,
        :phoenix_view
      ])
      |> Map.put(:host, conn.host)
      |> Map.put(:method, conn.method)
      |> Map.put(:path_info, conn.path_info)
      |> Map.put(:status, conn.status)
      |> Map.put(:duration, duration)

    put_entry(token, Debug, infos)
    :ok
  end

  def __handle_event__(_, _, _, _), do: :ok
end
