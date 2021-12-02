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

      {:telemetry, list(atom()), map(), map()}

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
    parent_ref = Process.monitor(parent)

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

    {:ok,
     %{
       parent_ref: parent_ref,
       parent: parent,
       ref: nil,
       root_pid: nil,
       transport: transport
     }}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, %{parent_ref: ref} = state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:DOWN, ref, _, _, reason}, %{ref: ref} = state) do
    notify_exception(state.parent, :exit, reason)
    {:noreply, %{state | ref: nil, root_pid: nil}}
  end

  def handle_info({:telemetry, event, measurements, metadata} = telemetry, state) do
    notify_telemetry(state.parent, telemetry)

    case event do
      [:phoenix, :live_view, stage, action] ->
        {_ref, state} = update_monitor(state, metadata.socket)
        handle_lifecycle(stage, action, measurements, metadata, state)

      _ ->
        {:noreply, state}
    end
  end

  defp handle_lifecycle(:mount, :stop, _, metadata, state) do
    notify_navigation(state.parent, metadata.socket)
    {:noreply, state}
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

  defp notify_exception(pid, %{kind: kind, reason: reason} = metadata) do
    notify_exception(pid, kind, reason, Map.get(metadata, :stacktrace, []))
  end

  defp notify_exception(pid, kind, reason) do
    notify_exception(pid, kind, reason, [])
  end

  defp notify_exception(pid, kind, reason, stacktrace) do
    send(pid, {:exception, kind, reason, stacktrace})
  end

  defp notify_navigation(pid, socket) do
    view =
      socket
      |> Map.take([:root_view, :root_pid])
      |> Map.put(:live_action, socket.assigns[:live_action])
      |> Map.put_new(:root_view, socket.private[:root_view])

    send(pid, {:navigation, view})
  end

  defp notify_telemetry(pid, {:telemetry, _, _, _} = telemetry) do
    send(pid, telemetry)
  end

  defp update_monitor(state, %{root_pid: pid} = socket) do
    if LiveView.connected?(socket) and state.root_pid != pid do
      if is_reference(state.ref), do: Process.demonitor(state.ref)
      {state.ref, %{state | ref: Process.monitor(pid), root_pid: pid}}
    else
      {state.ref, state}
    end
  end
end
