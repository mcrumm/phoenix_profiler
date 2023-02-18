defmodule PhoenixProfiler.Utils do
  @moduledoc false
  alias Phoenix.LiveView
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.Server

  @default_profiler_link_base "/dashboard/_profiler"

  @doc """
  Mounts the profile if it has been enabled on the endpoint.
  """
  def maybe_mount_profile(%LiveView.Socket{} = socket) do
    if LiveView.connected?(socket) and configured?(socket) do
      enable_profiler(socket)
    else
      socket
    end
  end

  defp configured?(conn_or_socket) do
    not is_nil(endpoint(conn_or_socket).config(:phoenix_profiler))
  end

  @doc """
  Enables the profiler on a given `conn` or `socket`.

  Raises if the profiler is not defined or is not started.
  For a LiveView socket, raises if the socket is not connected.
  """
  def enable_profiler(conn_or_socket) do
    endpoint = endpoint(conn_or_socket)
    config = endpoint.config(:phoenix_profiler, [])
    enable_profiler(conn_or_socket, endpoint, config, System.system_time())
  end

  @doc false
  def enable_profiler(conn_or_socket, _endpoint, nil, _system_time) do
    enable_profiler_error(conn_or_socket, :profiler_not_configured)
  end

  def enable_profiler(conn_or_socket, endpoint, config, system_time)
      when is_atom(endpoint) and is_list(config) and is_integer(system_time) do
    with :ok <- check_requires_profile(conn_or_socket),
         :ok <- maybe_check_socket_connection(conn_or_socket) do
      conn_or_socket
      |> new_profile(endpoint, config, system_time)
      |> start_profiling(config)
      |> telemetry_execute(:start, %{system_time: system_time})
    else
      {:error, reason} -> enable_profiler_error(conn_or_socket, reason)
    end
  end

  defp check_requires_profile(conn_or_socket) do
    case conn_or_socket.private do
      %{:phoenix_profiler => %Profile{}} ->
        {:error, :profile_already_exists}

      _ ->
        :ok
    end
  end

  defp maybe_check_socket_connection(%Plug.Conn{}), do: :ok

  defp maybe_check_socket_connection(%LiveView.Socket{} = socket) do
    check_socket_connection(socket)
  end

  defp new_profile(conn_or_socket, endpoint, config, system_time) do
    profiler_base_url = profiler_base_url(endpoint, config)

    {:ok, token} = Server.put_owner_token(owner_pid(conn_or_socket), endpoint)
    profile = Profile.new(endpoint, token, profiler_base_url, system_time)

    put_private(conn_or_socket, :phoenix_profiler, profile)
  end

  defp owner_pid(%Plug.Conn{} = conn), do: conn.owner
  defp owner_pid(%LiveView.Socket{} = socket), do: transport_pid(socket)

  defp profiler_base_url(endpoint, config) do
    endpoint.url() <> profiler_link_base(config[:profiler_link_base])
  end

  defp profiler_link_base(path) when is_binary(path) and path != "", do: path
  defp profiler_link_base(_), do: @default_profiler_link_base

  defp start_profiling(conn_or_socket, config) do
    Server.profiling(if config[:enable] == false, do: false, else: true)
    conn_or_socket
  end

  @doc """
  Returns the endpoint for a given `conn` or `socket`.
  """
  def endpoint(conn_or_socket)
  def endpoint(%Plug.Conn{} = conn), do: conn.private.phoenix_endpoint
  def endpoint(%LiveView.Socket{endpoint: endpoint}), do: endpoint

  defp enable_profiler_error(conn_or_socket, :profile_already_exists) do
    # notify state change and ensure profile info is :enable
    profile = %{conn_or_socket.private.phoenix_profiler | info: :enable}
    Server.profiling(true)
    put_private(conn_or_socket, :phoenix_profiler, profile)
  end

  defp enable_profiler_error(%LiveView.Socket{}, :waiting_for_connection) do
    raise """
    attempted to enable profiling on a disconnected socket

    In your LiveView mount callback, do the following:

        socket =
          if connected?(socket) do
            PhoenixProfiler.enable(socket)
          else
            socket
          end

    """
  end

  defp enable_profiler_error(_, :profiler_not_configured) do
    raise "attempted to enable profiling but no profiler is configured on the endpoint"
  end

  @doc """
  Disables the profiler on a given `conn` or `socket`.

  If a profile is not present on the data structure, this function has no effect.
  """
  def disable_profiler(%{__struct__: kind} = conn_or_socket)
      when kind in [Plug.Conn, LiveView.Socket] do
    _ = Server.profiling(false)
    conn_or_socket
  end

  def disable_profiler(%Plug.Conn{} = conn), do: conn
  def disable_profiler(%LiveView.Socket{} = socket), do: socket

  @doc """
  Checks whether or not a socket is connected.
  """
  @spec check_socket_connection(socket :: LiveView.Socket.t()) ::
          :ok | {:error, :waiting_for_connection}
  def check_socket_connection(%LiveView.Socket{} = socket) do
    if LiveView.connected?(socket) do
      :ok
    else
      {:error, :waiting_for_connection}
    end
  end

  @doc """
  Assigns a new private key and value in the socket.
  """
  def put_private(%Plug.Conn{} = conn, key, value) when is_atom(key) do
    Plug.Conn.put_private(conn, key, value)
  end

  def put_private(%LiveView.Socket{private: private} = socket, key, value) when is_atom(key) do
    %{socket | private: Map.put(private, key, value)}
  end

  # Unique ID generation
  # Copyright (c) 2013 Plataformatec.
  # https://github.com/elixir-plug/plug/blob/fb6b952cf93336dc79ec8d033e09a424d522ce56/lib/plug/request_id.ex
  @doc false
  def random_unique_id do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end

  @doc """
  Returns a map of system version metadata.
  """
  def system do
    for app <- [:otp, :elixir, :phoenix, :phoenix_live_view, :phoenix_profiler], into: %{} do
      {app, version(app)}
    end
  end

  defp version(:elixir), do: System.version()
  defp version(:otp), do: System.otp_release()

  defp version(app) when is_atom(app) do
    Application.spec(app)[:vsn]
  end

  @doc """
  Returns the `transport_pid` for a given `socket`.
  """
  # TODO: replace with `socket.transport_pid` when we require LiveView v0.16+.
  def transport_pid(%LiveView.Socket{} = socket) do
    Map.get_lazy(socket, :transport_pid, fn ->
      LiveView.transport_pid(socket)
    end)
  end

  @doc false
  def on_send_resp(conn, %Profile{} = profile) do
    duration = System.monotonic_time() - profile.start_time
    telemetry_execute(conn, :stop, %{duration: duration})
  end

  defp telemetry_execute(%LiveView.Socket{} = socket, _, _), do: socket

  defp telemetry_execute(%Plug.Conn{} = conn, action, measurements)
       when action in [:start, :stop] do
    :telemetry.execute([:phxprof, :plug, action], measurements, %{conn: conn})
    conn
  end

  @doc false
  def sort_by(enumerable, sort_by_fun, :asc) do
    Enum.sort_by(enumerable, sort_by_fun, &<=/2)
  end

  def sort_by(enumerable, sort_by_fun, :desc) do
    Enum.sort_by(enumerable, sort_by_fun, &>=/2)
  end

  # backwards compability
  if Version.match?(System.version(), ">= 1.10.0") do
    defdelegate map_pop!(map, key), to: Map, as: :pop!
  else
    # https://github.com/elixir-lang/elixir/blob/e29f1492a48c53ff41b4d60b6a7b5307692145f6/lib/elixir/lib/map.ex#L734
    def map_pop!(map, key) do
      case :maps.take(key, map) do
        {_, _} = tuple -> tuple
        :error -> raise KeyError, key: key, term: map
      end
    end
  end

  if String.to_integer(System.otp_release()) >= 24 do
    defdelegate queue_fold(func, initial, queue), to: :queue, as: :fold
  else
    # https://github.com/erlang/otp/blob/9f87c568cd3cdb621cf4cae69ccce880be4ea1b6/lib/stdlib/src/queue.erl#L442
    def queue_fold(func, initial, {r, f})
        when is_function(func, 2) and is_list(r) and is_list(f) do
      acc = :lists.foldl(func, initial, f)
      :lists.foldr(func, acc, r)
    end
  end
end
