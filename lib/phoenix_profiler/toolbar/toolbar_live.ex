defmodule PhoenixProfiler.ToolbarLive do
  # The LiveView for the Web Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:div, [class: "phxprof-toolbar-view"]}
  alias PhoenixProfiler.LiveViewListener
  alias PhoenixProfiler.Profiler
  alias PhoenixProfiler.Routes

  @impl Phoenix.LiveView
  def mount(_, %{"_" => %PhoenixProfiler.Profile{} = profile}, socket) do
    socket =
      socket
      |> assign_defaults()
      |> assign(:profile, profile)

    socket =
      case Profiler.remote_get(profile) do
        nil -> assign_error_toolbar(socket)
        remote_profile -> assign_toolbar(socket, remote_profile)
      end

    if connected?(socket) do
      LiveViewListener.listen(socket)
    end

    {:ok, socket, temporary_assigns: [exits: []]}
  end

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign_error_toolbar()}
  end

  defp assign_defaults(socket) do
    assign(socket,
      exits: [],
      exits_count: 0,
      memory: nil
    )
  end

  defp assign_error_toolbar(socket) do
    # Apply the minimal assigns when the profiler server is not started.
    # Usually this occurs after a node has been restarted and
    # a request is received for a stale token.
    assign(socket, %{
      durations: nil,
      request: %{
        status_code: ":|",
        status_phrase: "No Profiler Session (refresh)",
        endpoint: "n/a",
        router: "n/a",
        plug: "n/a",
        action: "n/a",
        router_helper: nil,
        class: "disconnected"
      }
    })
  end

  defp assign_toolbar(socket, profile) do
    %{metrics: metrics} = profile

    socket
    |> apply_request(profile)
    |> assign(:durations, %{
      total: duration(metrics.total_duration),
      endpoint: duration(metrics.endpoint_duration)
    })
    |> assign(:memory, memory(metrics.memory))
  end

  defp apply_request(socket, profile) do
    %{conn: %Plug.Conn{} = conn} = profile
    router = conn.private[:phoenix_router]
    {helper, plug, action} = Routes.info(socket.assigns.profile.node, conn)
    socket = %{socket | private: Map.put(socket.private, :phoenix_router, router)}

    assign(socket, :request, %{
      status_code: conn.status,
      status_phrase: Plug.Conn.Status.reason_phrase(conn.status),
      endpoint: inspect(Phoenix.Controller.endpoint_module(conn)),
      router: inspect(router),
      plug: inspect(plug),
      action: inspect(action),
      router_helper: helper,
      class: request_class(conn.status)
    })
  end

  defp update_view(socket, route) do
    update(socket, :request, fn req ->
      router = socket.private[:phoenix_router]

      {helper, plug, action} = Routes.info(socket.assigns.profile.node, router, route)

      %{req | plug: inspect(plug), action: inspect(action), router_helper: helper}
    end)
  end

  defp duration(duration) when is_integer(duration) do
    duration = System.convert_time_unit(duration, :native, :microsecond)

    if duration > 1000 do
      value = duration |> div(1000) |> Integer.to_string()
      %{value: value, label: "ms", phrase: "#{value} milliseconds"}
    else
      value = Integer.to_string(duration)
      %{value: value, label: "µs", phrase: "#{value} microseconds"}
    end
  end

  defp duration(_), do: nil

  defp memory(memory) do
    if memory > 1024 do
      value = memory |> div(1024) |> Integer.to_string()
      %{value: value, label: "MiB", phrase: "#{value} mebibytes"}
    else
      value = Integer.to_string(memory)
      %{value: value, label: "KiB", phrase: "#{value} kibibytes"}
    end
  end

  defp request_class(code) when is_integer(code) do
    case code do
      code when code >= 200 and code < 300 -> :green
      code when code >= 400 and code < 500 -> :red
      code when code >= 500 and code < 600 -> :red
      _ -> nil
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:exception, kind, reason, stacktrace}, socket) do
    apply_exception(socket, kind, reason, stacktrace)
  end

  def handle_info({:navigation, view}, socket) do
    {:noreply, update_view(socket, view)}
  end

  def handle_info(other, socket) do
    IO.inspect(other, label: "ToolbarLive received an unknown message")
    {:noreply, socket}
  end

  defp apply_exception(socket, kind, reason, stacktrace) do
    exception = %{
      ref: Phoenix.LiveView.Utils.random_id(),
      reason: Exception.format(kind, reason, stacktrace),
      at: Time.utc_now() |> Time.truncate(:second)
    }

    {:noreply,
     socket
     |> update(:exits, &[exception | &1])
     |> update(:exits_count, &(&1 + 1))}
  end
end
