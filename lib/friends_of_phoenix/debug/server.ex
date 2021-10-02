defmodule FriendsOfPhoenix.Debug.Server do
  # Debug server store info for the toolbar
  @moduledoc false
  use GenServer, restart: :temporary
  alias FriendsOfPhoenix.Debug
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @token_key Debug.token_key()

  ## Client

  def start_link(opts) do
    token = opts[:token] || raise "token is required to start the debug server"
    GenServer.start_link(__MODULE__, token, name: server_name(token))
  end

  def server_name(token) when is_binary(token) do
    Module.concat([Debug, Server, token])
  end

  @doc """
  Returns the `Debug.PubSub` topic for the given `token`.
  """
  def topic(token) when is_binary(token) and token != "" do
    "fophx_debug:#{token}"
  end

  @doc """
  Returns a map of info collected by the Plug.
  """
  def info(token) do
    case Process.whereis(server_name(token)) do
      server when is_pid(server) ->
        GenServer.call(server, :fophx_debug_info)

      _ ->
        IO.warn("""
        Tried to retrieve request info for token #{token}, but the server is not running.

        If you are seeing this message after restarting the server in the dev environment,
        it is likely safe to ignore. Debug processes are ephemeral, so if the server was
        killed, then you are seeing this warning due to the stale session cookie sent from
        your browser.

        If the debug toolbar is not rendered, refresh the page to reload.
        """)

        %{}
    end
  end

  ## Server

  @impl GenServer
  def init(token) do
    :ok = PubSub.subscribe(Debug.PubSub, topic(token))

    :ok =
      :telemetry.attach(
        {Debug, token},
        [:fophx, :debug, :stop],
        &__MODULE__.__handle_event__/4,
        %{
          token: token
        }
      )

    {:ok, %{token: token, debug_info: %{}}}
  end

  @impl GenServer
  def handle_call(:fophx_debug_info, _from, state) do
    {:reply, state.debug_info, state}
  end

  @impl GenServer
  def handle_call({:put_debug_info, info}, _from, state) do
    {:reply, :ok, %{state | debug_info: info}}
  end

  @impl GenServer
  def handle_info(%Broadcast{event: "presence_diff", payload: payload}, state) do
    # %{joins: joins, leaves: leaves} = payload
    IO.inspect(payload, label: "Got message:")
    {:noreply, state}
  end

  ## Telemetry Handlers

  @doc false
  def __handle_event__(
        [:fophx, :debug, :stop],
        %{duration: duration},
        %{conn: %{private: %{@token_key => token}} = conn},
        %{token: token}
      ) do
    info =
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

    case Process.whereis(server_name(token)) do
      pid when is_pid(pid) -> GenServer.call(pid, {:put_debug_info, info})
      _ -> :ok
    end
  end

  def __handle_event__(_, _, _, _), do: :ok
end
