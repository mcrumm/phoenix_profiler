defmodule PhoenixWeb.Profiler.Server do
  # Profiler server store info for the toolbar
  @moduledoc false
  use GenServer, restart: :temporary
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.Session
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

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

  ## Server

  @impl GenServer
  def init(session_token) do
    topic = Profiler.Server.topic(session_token)
    :ok = PubSub.subscribe(Profiler.PubSub, topic)
    {:ok, %{session: session_token, topic: topic, requests: %{}}}
  end

  @impl GenServer
  def handle_info(%Broadcast{event: "presence_diff", payload: payload}, state) do
    %{joins: joins, leaves: leaves} = payload

    updated_requests =
      state.requests
      |> handle_leaves(leaves)
      |> handle_joins(joins)

    {:noreply, %{state | requests: updated_requests}}
  end

  defp handle_leaves(requests, leaves) do
    Enum.reduce(leaves, requests, fn {debug_token, %{metas: metas}}, requests ->
      Map.update!(requests, debug_token, fn request ->
        Enum.reduce(metas, request, fn
          %{kind: :toolbar, pid: pid}, %{toolbar: pid} = request ->
            %{request | toolbar: nil}

          %{kind: :profile, pid: pid}, %{view: pid} = request ->
            %{request | view: nil, message: nil}
        end)
      end)
    end)
  end

  defp handle_joins(requests, joins) do
    Enum.reduce(joins, requests, fn {debug_token, %{metas: metas}}, requests ->
      requests
      |> Map.put_new_lazy(debug_token, &build_request/0)
      |> Map.update!(debug_token, fn request ->
        Enum.reduce(metas, request, fn
          %{kind: :toolbar, pid: pid}, request ->
            # Profile won the race, send the latent join
            if message = request.message do
              send(pid, {Session, :join, message})
            end

            %{request | toolbar: pid, message: nil}

          %{kind: :profile, pid: pid} = join, %{toolbar: nil} = request ->
            # Profile won the race - queue the join
            %{request | view: pid, message: join}

          %{kind: :profile, pid: pid}, request ->
            # Toolbar won the race– it will get the join
            %{request | view: pid, message: nil}
        end)
      end)
    end)
  end

  defp build_request do
    %{toolbar: nil, view: nil, message: nil}
  end
end
