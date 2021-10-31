defmodule PhoenixWeb.Profiler.ToolbarLive do
  # The LiveView for the Web Debug Toolbar
  @moduledoc false
  use Phoenix.LiveView, container: {:div, [class: "phxweb-toolbar-view"]}
  alias PhoenixWeb.Profiler.{Presence, Routes, Session}

  @cast_for_dumped_wait 100
  @debug_key Session.token_key()

  @impl Phoenix.LiveView
  def mount(_, %{@debug_key => token} = session, socket) do
    socket =
      socket
      |> assign(:token, token)
      |> put_private(:topic, Session.topic(session))
      |> Session.track(session, %{kind: :toolbar})
      |> Session.subscribe()
      |> put_private(:dumped_ref, nil)
      |> put_private(:monitor_ref, nil)

    socket =
      assign(socket,
        dumped: [],
        dumped_count: 0,
        exits: [],
        exits_count: 0,
        memory: nil,
        system: system()
      )

    socket =
      case Session.info(session) do
        nil ->
          assign_minimal_toolbar(socket)

        info ->
          socket = put_private(socket, :profilerinfo, info)
          assign_toolbar(socket, info)
      end

    {:ok, socket, temporary_assigns: [exits: []]}
  end

  def mount(_, _, socket) do
    {:ok, assign_minimal_toolbar(socket)}
  end

  defp assign_minimal_toolbar(socket) do
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
    %{dumped: dumped, metrics: metrics, route: route} = profile

    socket
    |> apply_request(profile)
    |> update_view(route)
    |> update_dumped(dumped)
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
      toolbar_version: Application.spec(:phoenix_web_profiler)[:vsn]
    }
  end

  defp update_dumped(socket, dumped) when is_list(dumped) do
    socket
    |> update(:dumped, &(dumped ++ (&1 || [])))
    |> update(:dumped_count, &(&1 + length(dumped)))
  end

  @impl Phoenix.LiveView
  def handle_cast({:dumped, ref, flushed}, %{private: %{dumped_ref: ref}} = socket)
      when is_reference(ref) do
    Process.send_after(self(), :cast_for_dumped, @cast_for_dumped_wait)

    {:noreply,
     socket
     |> update_dumped(flushed)
     |> put_private(:dumped_ref, nil)}
  end

  # stale dumped ref
  def handle_cast({:dumped, ref, _flushed}, %{private: %{dumped_ref: _}} = socket)
      when is_reference(ref) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: _payload}, socket) do
    # assumes only one process under profile per debug token.
    # a unique debug token is generated per stateless request,
    # so that should be a safe assumption.
    view_or_nil =
      socket.private.topic
      |> Presence.list()
      |> get_in([socket.assigns.token, :metas])
      |> Kernel.||([])
      |> Enum.find(&(&1.kind == :profile))

    socket = update_monitor(socket, view_or_nil)
    {:noreply, assign_view(socket, view_or_nil)}
  end

  def handle_info(
        {:DOWN, ref, _, _pid, reason},
        %{private: %{monitor_ref: ref}} = socket
      ) do
    socket =
      case reason do
        {:shutdown, :left} ->
          socket

        {:shutdown, :duplicate_join} ->
          socket

        :shutdown ->
          socket

        other ->
          apply_exit_reason(socket, other)
      end

    {:noreply, clear_monitor(socket)}
  end

  def handle_info({Session, :join, %{phx_ref: ref}}, %{private: %{last_join_ref: ref}} = socket) do
    {:noreply, socket}
  end

  def handle_info({Session, :join, join}, socket) do
    socket = update_monitor(socket, join)
    {:noreply, update_view(socket, join)}
  end

  def handle_info(:cast_for_dumped, %{private: %{lv_pid: pid}} = socket) when is_pid(pid) do
    {:noreply, cast_for_dumped(socket, pid)}
  end

  def handle_info(:cast_for_dumped, socket) do
    {:noreply, socket}
  end

  def handle_info({PhoenixWeb.LiveProfiler, :ping, _ref}, socket) do
    {:noreply, socket}
  end

  def handle_info(other, socket) do
    IO.inspect(other, label: "ToolbarLive received an unknown message")
    {:noreply, socket}
  end

  defp apply_exit_reason(socket, reason) do
    exit_reason = %{
      ref: Phoenix.LiveView.Utils.random_id(),
      reason: Exception.format_exit(reason),
      at: Time.utc_now() |> Time.truncate(:second)
    }

    socket
    |> update(:exits, &[exit_reason | &1])
    |> update(:exits_count, &(&1 + 1))
  end

  defp clear_monitor(%{private: private} = socket) do
    private = private |> Map.delete(:monitor_ref) |> Map.delete(:lv_pid)
    %{socket | private: private}
  end

  # no process under profile
  defp update_monitor(socket, nil) do
    socket
  end

  # process under profile did not change
  defp update_monitor(%{private: %{lv_pid: pid}} = socket, %{pid: pid}) do
    socket
  end

  # process under profile did change
  defp update_monitor(%{private: %{monitor_ref: ref}} = socket, view) when is_reference(ref) do
    Process.demonitor(ref)
    do_monitor_view(socket, view)
  end

  # set process under profile
  defp update_monitor(socket, view) do
    do_monitor_view(socket, view)
  end

  defp do_monitor_view(socket, %{pid: pid, phx_ref: phx_ref}) do
    ref = Process.monitor(pid)
    socket = cast_for_dumped(socket, pid)

    private =
      socket.private
      |> Map.put(:last_join_ref, phx_ref)
      |> Map.put(:monitor_ref, ref)
      |> Map.put(:lv_pid, pid)

    %{socket | private: private}
  end

  defp assign_view(socket, nil), do: socket

  defp assign_view(socket, view) do
    update_view(socket, view)
  end

  defp cast_for_dumped(%Phoenix.LiveView.Socket{} = socket, pid)
       when is_pid(pid) do
    dumped_ref = make_ref()
    GenServer.cast(pid, {PhoenixWeb.LiveProfiler, {:dump, dumped_ref}, to: self()})

    put_private(socket, :dumped_ref, dumped_ref)
  end

  defp put_private(%Phoenix.LiveView.Socket{private: private} = socket, key, value)
       when is_atom(key) do
    private = Map.put(private, key, value)
    %{socket | private: private}
  end

  defp format_module_function(module, {function, arity}) do
    "#{module}.#{function}/#{arity}"
  end
end
