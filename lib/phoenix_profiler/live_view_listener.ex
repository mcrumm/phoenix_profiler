defmodule PhoenixProfiler.LiveViewListener do
  # This module is the one responsible for listening to
  # LiveView telemetry events and collecting data from a given transport.
  @moduledoc false
  use GenServer, restart: :temporary
  alias Phoenix.LiveView

  @doc """
  Subscribes the caller to updates about a given transport.

  ## Events

  The following events are emitted:

      {:navigation, %{live_action: atom(), root_pid: pid(), root_view: atom()}}

      {:exception, kind :: Exception.kind(), reason :: any(), stacktrace :: Exception.stacktrace()}

  """
  def listen(%LiveView.Socket{} = socket) do
    listen(socket, [])
  end

  def listen(%LiveView.Socket{} = socket, opts) do
    unless LiveView.connected?(socket) do
      raise ArgumentError, "listen/2 may only be called when the socket is connected."
    end

    # TODO: replace it with `socket.transport_pid` when we support only LiveView 0.16+
    transport_pid =
      Map.get_lazy(socket, :transport_pid, fn ->
        LiveView.transport_pid(socket)
      end)

    listen(node(), transport_pid, opts)
  end

  def listen(node, transport, opts) when is_pid(transport) do
    DynamicSupervisor.start_child(
      {PhoenixProfiler.DynamicSupervisor, node},
      {__MODULE__, {self(), transport, opts}}
    )
  end

  def start_link({parent, transport, opts}) do
    GenServer.start_link(__MODULE__, {parent, transport, opts})
  end

  @impl true
  def init({parent, transport, _opts}) do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(parent)

    events =
      for stage <- [:mount, :handle_params, :handle_event],
          action <- [:start, :stop, :exception] do
        [:phoenix, :live_view, stage, action]
      end

    :telemetry.attach_many(
      {__MODULE__, self()},
      events,
      &__MODULE__.telemetry_callback/4,
      %{listener: self(), parent: parent, transport: transport}
    )

    {:ok, %{parent: parent, ref: ref, root_pid: nil, transport: transport}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, %{ref: ref} = state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:telemetry, [:phoenix, :live_view | _] = event, measurements, metadata}, state) do
    [_, _, stage, action] = event

    state =
      state
      |> check_navigation(metadata.socket)
      |> handle_lifecycle(stage, action, measurements, metadata)
      |> handle_event_duration([stage, action], measurements)

    {:noreply, state}
  end

  defp handle_lifecycle(state, _stage, :exception, _measurements, metadata) do
    notify_exception(state.parent, metadata)
    state
  end

  defp handle_lifecycle(state, _stage, _action, _measurements, _metadata) do
    state
  end

  defp handle_event_duration(state, [:handle_event, :stop], %{duration: duration}) do
    notify_event_duration(state.parent, duration)
    state
  end

  defp handle_event_duration(state, _event, _measurements) do
    state
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach({__MODULE__, self()})

    :ok
  end

  def telemetry_callback(
        [:phoenix, :live_view | _] = event,
        measurements,
        %{
          socket: %{
            transport_pid: transport,
            root_pid: pid,
            private: %{phxprof_enabled: {_, ref}}
          }
        } = metadata,
        %{parent: parent, transport: transport} = context
      )
      when is_pid(pid) and is_pid(parent) and pid != parent and is_reference(ref) do
    send(context.listener, {:telemetry, event, measurements, metadata})
  end

  def telemetry_callback(_, _, _, _), do: :ok

  defp check_navigation(state, %{root_pid: pid} = socket) do
    if LiveView.connected?(socket) and state.root_pid != pid do
      notify_navigation(state.parent, socket)
      %{state | root_pid: pid}
    else
      state
    end
  end

  defp notify_exception(pid, %{kind: kind, reason: reason} = metadata) do
    send(pid, {:exception, kind, reason, Map.get(metadata, :stacktrace, [])})
  end

  defp notify_navigation(pid, socket) do
    view =
      socket
      |> Map.take([:root_view, :root_pid])
      |> Map.put(:live_action, socket.assigns[:live_action])
      |> Map.put_new(:root_view, socket.private[:root_view])

    send(pid, {:navigation, view})
  end

  defp notify_event_duration(pid, duration) do
    send(pid, {:event_duration, duration})
  end
end
