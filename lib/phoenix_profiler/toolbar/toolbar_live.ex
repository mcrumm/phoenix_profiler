defmodule PhoenixProfiler.ToolbarLive do
  # The LiveView for the Web Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:div, [class: "phxprof-toolbar-view"]}
  require Logger
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfiler.Routes

  toolbar_css_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.css")
  @external_resource toolbar_css_path

  toolbar_js_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.js")
  @external_resource toolbar_js_path

  @toolbar_css File.read!(toolbar_css_path)
  @toolbar_js File.read!(toolbar_js_path)

  def toolbar(assigns) do
    assigns = Map.put(assigns, :toolbar_css, @toolbar_css)
    assigns = Map.put(assigns, :toolbar_js, @toolbar_js)

    ~H"""
    <!-- START Phoenix Web Debug Toolbar -->
    <div {@toolbar_attrs}>
      <div class="phxprof-minitoolbar"><button class="show-button" type="button" id={"phxprof-toolbar-show-#{@profile.token}"} title="Show Toolbar" accesskey="D" aria-expanded="true" aria-controls={"phxprof-toolbar-main-#{@profile.token}"}></button></div>
      <div id={"phxprof-toolbar-clearer-#{@profile.token}"} class="phxprof-toolbar-clearer" style="display: block;"></div>
      <%= live_render(@conn, __MODULE__, session: @session) %>
    </div>
    <script><%= Phoenix.HTML.raw(@toolbar_js) %></script>
    <style type="text/css"><%= Phoenix.HTML.raw(@toolbar_css) %></style>
    <!-- END Phoenix Web Debug Toolbar -->
    """
  end

  @impl Phoenix.LiveView
  def mount(_, %{"_" => %PhoenixProfiler.Profile{} = profile}, socket) do
    socket =
      socket
      |> assign_defaults()
      |> assign(:profile, profile)

    socket =
      case ProfileStore.remote_get(profile) do
        nil -> assign_error_toolbar(socket)
        remote_profile -> assign_toolbar(socket, remote_profile)
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
      durations: nil,
      exits: [],
      exits_count: 0,
      memory: nil,
      root_pid: nil
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
      endpoint: duration(metrics.endpoint_duration),
      latest_event: nil
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

  defp apply_navigation(socket, %{router: router} = route) do
    socket
    |> update(:root_pid, fn _ -> route.root_pid end)
    |> update(:request, fn req ->
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
  def handle_info({:telemetry, _, [:phoenix, :live_view, _, _] = event, _event_ts, data}, socket) do
    [_, _, stage, action] = event

    socket =
      socket
      |> maybe_apply_navigation(data)
      |> apply_lifecycle(stage, action, data)
      |> apply_event_duration(stage, action, data)

    {:noreply, socket}
  end

  def handle_info(other, socket) do
    Logger.debug("ToolbarLive received an unknown message: #{inspect(other)}")
    {:noreply, socket}
  end

  defp maybe_apply_navigation(socket, data) do
    if connected?(socket) and not is_nil(data.router) and
         socket.assigns.root_pid != data.root_pid do
      apply_navigation(socket, data)
    else
      socket
    end
  end

  defp apply_lifecycle(socket, _stage, :exception, data) do
    %{kind: kind, reason: reason, stacktrace: stacktrace} = data

    exception = %{
      ref: Phoenix.LiveView.Utils.random_id(),
      reason: Exception.format(kind, reason, stacktrace),
      at: Time.utc_now() |> Time.truncate(:second)
    }

    socket
    |> update(:exits, &[exception | &1])
    |> update(:exits_count, &(&1 + 1))
  end

  defp apply_lifecycle(socket, _stage, _action, _data) do
    socket
  end

  defp apply_event_duration(socket, stage, :stop, %{duration: duration})
       when stage in [:handle_event, :handle_params] do
    update(socket, :durations, fn durations ->
      durations = durations || %{total: nil, endpoint: nil, latest_event: nil}
      %{durations | latest_event: duration(duration)}
    end)
  end

  defp apply_event_duration(socket, _stage, _action, _measurements) do
    socket
  end

  defp current_duration(durations) do
    if event = durations.latest_event,
      do: {event.value, event.label},
      else: {durations.total.value, durations.total.label}
  end
end
