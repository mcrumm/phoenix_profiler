defmodule PhoenixWeb.Profiler.ToolbarLive do
  # The LiveView for the Web Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:div, [class: "phxweb-toolbar-view"]}
  alias PhoenixProfiler.{LiveViewListener, Requests}
  alias PhoenixWeb.Profiler.Routes

  @impl Phoenix.LiveView
  def mount(_, %{"node" => node, "token" => token}, socket) do
    socket =
      socket
      |> assign_defaults()
      |> assign(:system, system())
      |> assign(:token, token)

    socket =
      case Requests.remote_get(node, token) do
        nil -> assign_error_toolbar(socket)
        profile -> assign_toolbar(socket, profile)
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
        icon_value: nil,
        class: "disconnected"
      }
    })
  end

  defp assign_toolbar(socket, profile) do
    %{metrics: metrics, route: route} = profile

    socket
    |> apply_request(profile)
    |> update_view(route)
    |> assign(:durations, %{
      total: duration(metrics.total_duration),
      endpoint: duration(metrics.endpoint_duration)
    })
    |> assign(:memory, memory(metrics.memory))
  end

  defp apply_request(socket, profile) do
    %{conn: %Plug.Conn{} = conn, route: route} = profile

    assign(socket, :request, %{
      status_code: conn.status,
      status_phrase: Plug.Conn.Status.reason_phrase(conn.status),
      endpoint: inspect(Phoenix.Controller.endpoint_module(conn)),
      router: inspect(conn.private[:phoenix_router]),
      plug: route[:plug],
      action: route[:plug_opts],
      icon_value: nil,
      class: request_class(conn.status)
    })
  end

  defp update_view(socket, route) do
    update(socket, :request, fn req ->
      router = get_in(socket.private, [:profilerinfo, :phoenix_router])
      {helper, plug, action} = Routes.guess_helper(router, route)
      %{req | plug: inspect(plug), action: inspect(action), icon_value: helper}
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

  defp system do
    %{
      elixir_version: System.version(),
      phoenix_version: Application.spec(:phoenix)[:vsn],
      live_view_version: Application.spec(:phoenix_live_view)[:vsn],
      otp_release: System.otp_release(),
      toolbar_version: Application.spec(:phoenix_profiler)[:vsn]
    }
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
