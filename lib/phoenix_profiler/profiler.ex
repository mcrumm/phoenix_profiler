defmodule PhoenixProfiler.Profiler do
  @moduledoc false
  use Supervisor
  alias Phoenix.LiveView
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfiler.Telemetry
  alias PhoenixProfiler.TelemetryServer
  alias PhoenixProfiler.Utils

  @doc """
  Builds a profile from data collected for a given `conn`.
  """
  def collect(%Plug.Conn{} = conn) do
    if conn.private.phoenix_profiler_info == :enable do
      time = System.system_time()
      profiler_base_url = conn.private.phoenix_profiler_base_url
      token = Map.get_lazy(conn.private, :phoenix_profiler_token, &Utils.random_unique_id/0)

      data =
        PhoenixProfiler.TelemetryCollector.reduce(
          conn.private.phoenix_profiler_collector,
          %{metrics: %{endpoint_duration: nil}},
          fn
            {:telemetry, _, _, _, %{endpoint_duration: duration}}, acc ->
              %{acc | metrics: Map.put(acc.metrics, :endpoint_duration, duration)}

            {:telemetry, _, _, _, %{metrics: _} = entry}, acc ->
              {metrics, rest} = Utils.map_pop!(entry, :metrics)
              acc = Map.merge(acc, rest)
              %{acc | metrics: Map.merge(acc.metrics, metrics)}

            {:telemetry, _, _, _, data}, acc ->
              Map.merge(acc, data)
          end
        )

      profile =
        Profile.new(
          conn.private.phoenix_profiler,
          token,
          profiler_base_url,
          time
        )

      {:ok, %Profile{profile | data: data}}
    else
      :error
    end
  end

  @doc """
  Inserts a profile into term storage.
  """
  def insert_profile(%Profile{} = profile) do
    profile
    |> ProfileStore.table()
    |> :ets.insert({profile.token, profile})
  end

  @doc """
  Disables profiling for a given `conn` or `socket`.
  """
  def disable(conn_or_socket) do
    update_info(conn_or_socket, :disable)
  end

  @doc """
  Enables profiling for a given `conn` or `socket`.
  """
  def enable(conn_or_socket) do
    update_info(conn_or_socket, :enable)
  end

  @doc """
  Configures profiling for a given `conn` or `socket`.
  """
  def configure(conn_or_socket, endpoint \\ nil) do
    case validate_apply_configuration(conn_or_socket, endpoint) do
      {:ok, conn_or_socket} ->
        {:ok, conn_or_socket}

      {:error, :profiler_not_available} ->
        {:error, :profiler_not_available}

      {:error, reason} ->
        configure_profile_error(conn_or_socket, :configure, reason)
    end
  end

  def start_link(opts) do
    {name, opts} = opts |> Enum.into([]) |> Keyword.pop(:name)

    unless name do
      raise ArgumentError, "the :name option is required to start PhoenixProfiler"
    end

    Supervisor.start_link(__MODULE__, {name, opts}, name: name)
  end

  @impl Supervisor
  def init({name, opts}) do
    events = (opts[:telemetry] || []) ++ Telemetry.events()

    children = [
      {ProfileStore, {name, opts}},
      {TelemetryServer, [filter: &Telemetry.collect/4, server: name, events: events]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp update_info(conn_or_socket, action) when action in [:disable, :enable] do
    TelemetryServer.collector_info_exec(action)
    Utils.put_private(conn_or_socket, :phoenix_profiler_info, action)
  end

  def apply_configuration(conn_or_socket, endpoint, server, config)
      when is_atom(endpoint) and is_atom(server) do
    info = if config[:enable] == false, do: :disable, else: :enable
    base_url = endpoint.url() <> Utils.profile_base_path(config)
    {:ok, collector_pid} = start_collector(conn_or_socket, server, info)

    conn_or_socket
    |> Utils.put_private(:phoenix_profiler, server)
    |> Utils.put_private(:phoenix_profiler_base_url, base_url)
    |> Utils.put_private(:phoenix_profiler_collector, collector_pid)
    |> Utils.put_private(:phoenix_profiler_info, info)
    |> Utils.put_private(:phoenix_profiler_token, Utils.random_unique_id())
  end

  defp validate_apply_configuration(conn_or_socket, endpoint) do
    endpoint = endpoint || Utils.endpoint(conn_or_socket)

    with {:ok, config} <- Utils.check_configuration(endpoint),
         :ok <- maybe_check_socket_connection(conn_or_socket),
         {:ok, profiler} <- check_profiler_running(config) do
      {:ok, apply_configuration(conn_or_socket, endpoint, profiler, config)}
    end
  end

  defp maybe_check_socket_connection(%Plug.Conn{}), do: :ok

  defp maybe_check_socket_connection(%LiveView.Socket{} = socket) do
    Utils.check_socket_connection(socket)
  end

  defp check_profiler_running(config) do
    profiler = config[:server]

    cond do
      GenServer.whereis(profiler) ->
        {:ok, profiler}

      profiler ->
        {:error, :profiler_not_running}

      true ->
        {:error, :profiler_not_available}
    end
  end

  # We do not start a collector for a LiveView Socket–
  # ToolbarLive will register itself as a collector for its
  # Socket's transport_pid.
  defp start_collector(%LiveView.Socket{}, _, _) do
    {:ok, nil}
  end

  defp start_collector(conn_or_socket, server, info) do
    case TelemetryServer.listen(server, Utils.target_pid(conn_or_socket), nil, info) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_registered, pid}} ->
        TelemetryServer.collector_info_exec(info)
        {:ok, pid}
    end
  end

  defp configure_profile_error(%LiveView.Socket{}, action, :waiting_for_connection) do
    raise """
    "PhoenixProfiler attempted to #{action} a profiler on the given socket, but it is disconnected

    In your LiveView mount callback, do the following:

        socket =
          if connected?(socket) do
            PhoenixProfiler.enable(socket)
          else
            socket
          end

    """
  end

  defp configure_profile_error(%{__struct__: struct}, action, :profiler_not_running) do
    raise "PhoenixProfiler attempted to #{action} a profiler " <>
            "on the given #{kind(struct)}, but the profiler is not running"
  end

  defp kind(Plug.Conn), do: :conn
  defp kind(LiveView.Socket), do: :socket
end
