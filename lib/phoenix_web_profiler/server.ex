defmodule PhoenixWeb.Profiler.Server do
  # Profiler server store info for the toolbar
  @moduledoc false
  use GenServer, restart: :temporary
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.{Request, Session}
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @private_key Request.session_key()
  @session_key Session.session_key()

  ## Client

  def start_link(opts) do
    token = opts[:token] || raise "token is required to start the profiler server"
    GenServer.start_link(__MODULE__, token, name: server_name(token))
  end

  def server_name(token) when is_binary(token) do
    Module.concat([Profiler, Server, token])
  end

  @doc """
  Returns the `Profiler.PubSub` topic for the given `token`.
  """
  def topic(token) when is_binary(token) and token != "" do
    "#{@session_key}:#{token}"
  end

  @doc """
  Returns the pid for a given `token` or nil.
  """
  def whereis(token) do
    token |> server_name() |> Process.whereis()
  end

  @doc """
  Returns a map of info collected by the Plug.
  """
  def info(session_token, debug_token) do
    case whereis(session_token) do
      server when is_pid(server) ->
        GenServer.call(server, {:fetch_profile, {Request, debug_token}})

      _ ->
        {:error, :not_started}
    end
  end

  ## Server

  @impl GenServer
  def init(session_token) do
    :ok = PubSub.subscribe(Profiler.PubSub, topic(session_token))
    {:ok, %{session: session_token, profiles: %{}, toolbar: nil, current_view: nil}}
  end

  @impl GenServer
  def handle_call(
        {:store, Request, %{@private_key => session} = profile},
        _from,
        %{session: session} = state
      ) do
    {:reply, :ok, %{state | profiles: Map.put(state.profiles, Request, profile)}}
  end

  @impl GenServer
  def handle_call({:fetch_profile, {Request, _debug_token}}, _from, state) do
    {:reply, {:ok, get_in(state.profiles, [Request])}, state}
  end

  @impl GenServer
  def handle_info(%Broadcast{event: "presence_diff", payload: _payload}, state) do
    presences =
      state.session
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
