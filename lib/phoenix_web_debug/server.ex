defmodule PhoenixWeb.Profiler.Server do
  # Profiler server store info for the toolbar
  @moduledoc false
  use GenServer, restart: :temporary
  alias PhoenixWeb.Profiler
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @token_key Profiler.token_key()

  ## Client

  @doc """
  Starts a profiler server for a given `conn`.

  The `conn` must have already been provided a debug token.
  """
  def profile(conn, extra \\ %{})

  def profile(%Plug.Conn{private: %{@token_key => token}} = conn, extra) do
    request_info = Map.take(conn, [:host, :method, :path_info, :status])

    metadata =
      Map.take(conn.private, [
        :phoenix_action,
        :phoenix_controller,
        :phoenix_endpoint,
        :phoenix_router,
        :phoenix_view
      ])

    debug_info =
      extra
      |> Map.new()
      |> Map.merge(request_info)
      |> Map.merge(metadata)

    DynamicSupervisor.start_child(
      Profiler.DynamicSupervisor,
      {Profiler.Server, token: token, debug_info: debug_info}
    )
  end

  def profile(%Plug.Conn{} = _conn, _extra) do
    raise "debug token required to be set for profile/2"
  end

  def start_link(opts) do
    token = opts[:token] || raise "token is required to start the profiler server"
    info = opts[:debug_info] || %{}
    GenServer.start_link(__MODULE__, {token, info}, name: server_name(token))
  end

  def server_name(token) when is_binary(token) do
    Module.concat([Profiler, Server, token])
  end

  @doc """
  Returns the `Profiler.PubSub` topic for the given `token`.
  """
  def topic(token) when is_binary(token) and token != "" do
    "#{@token_key}:#{token}"
  end

  @doc """
  Returns a map of info collected by the Plug.
  """
  def info(token) do
    case Process.whereis(server_name(token)) do
      server when is_pid(server) ->
        GenServer.call(server, :fetch_debug_info)

      _ ->
        {:error, :not_started}
    end
  end

  ## Server

  @impl GenServer
  def init({token, debug_info}) do
    :ok = PubSub.subscribe(Profiler.PubSub, topic(token))
    {:ok, %{token: token, debug_info: debug_info, toolbar: nil, current_view: nil}}
  end

  @impl GenServer
  def handle_call(:fetch_debug_info, _from, state) do
    {:reply, {:ok, state.debug_info}, state}
  end

  @impl GenServer
  def handle_info(%Broadcast{event: "presence_diff", payload: _payload}, state) do
    presences =
      state.token
      |> Profiler.Server.topic()
      |> Profiler.Presence.list()
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)

    # naive pid finding
    toolbar = Enum.find_value(presences, &if(&1.kind == :toolbar, do: {&1.pid, &1.node}))
    view = Enum.find(presences, &(&1.kind == :profile))

    # TODO: new operation
    #
    # :profile presence
    #   if the view changed, check for toolbar
    #   yes toolbar -> no-op
    #   no toolbar -> queue the change
    #
    # :toolbar presence
    #   on join -> send any view changes in the queue
    #   on leave -> remove toolbar from state
    state =
      state
      |> maybe_put_toolbar(toolbar)
      |> maybe_put_current_view(view)

    {:noreply, state}
  end

  defp maybe_put_toolbar(state, nil), do: state
  defp maybe_put_toolbar(%{toolbar: {pid, _}} = state, {pid, _}) when is_pid(pid), do: state

  defp maybe_put_toolbar(state, {pid, _} = name) when is_pid(pid) do
    %{state | toolbar: name}
  end

  defp maybe_put_current_view(state, nil), do: state

  defp maybe_put_current_view(state, %{pid: pid} = view) when is_pid(pid) do
    %{state | current_view: view}
  end
end
