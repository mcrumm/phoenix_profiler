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

      {:exception, atom(), any(), list()}

  """
  def listen(%LiveView.Socket{transport_pid: transport}) do
    listen(transport, [])
  end

  def listen(%LiveView.Socket{transport_pid: transport}, opts) do
    listen(transport, opts)
  end

  def listen(node \\ node(), transport, opts) when is_pid(transport) do
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

    :telemetry.attach_many(
      {__MODULE__, self()},
      [
        [:phoenix, :live_view, :mount, :start],
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :mount, :exception],
        [:phoenix, :live_view, :handle_params, :start],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :handle_params, :exception],
        [:phoenix, :live_view, :handle_event, :start],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :handle_event, :exception]
      ],
      &__MODULE__.telemetry_callback/4,
      %{listener: self(), parent: parent, transport: transport}
    )

    {:ok, %{parent: parent, ref: ref, root_pid: nil, transport: transport}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, %{ref: ref} = state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:telemetry, event, measurements, metadata}, state) do
    case event do
      [:phoenix, :live_view, stage, action] ->
        state = check_navigation(state, metadata.socket)
        handle_lifecycle(stage, action, measurements, metadata, state)

      _ ->
        {:noreply, state}
    end
  end

  defp handle_lifecycle(_stage, :exception, _measurements, metadata, state) do
    notify_exception(state.parent, metadata)
    {:noreply, state}
  end

  defp handle_lifecycle(_stage, _action, _measurements, _metadata, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach({__MODULE__, self()})

    :ok
  end

  def telemetry_callback(
        [:phoenix, :live_view | _] = event,
        measurements,
        %{socket: %{transport_pid: transport, root_pid: pid}} = metadata,
        %{parent: parent, transport: transport} = context
      )
      when is_pid(pid) and is_pid(parent) and pid != parent do
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
end
