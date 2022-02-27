defmodule PhoenixProfiler.Profiler do
  @moduledoc false
  use Supervisor
  alias Phoenix.LiveView
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfiler.Telemetry
  alias PhoenixProfiler.TelemetryServer
  alias PhoenixProfiler.Utils

  @default_profiler_link_base "/dashboard/_profiler"

  @doc """
  Builds a profile from data collected for a given `conn`.
  """
  def collect(%Plug.Conn{} = conn) do
    endpoint = conn.private.phoenix_endpoint
    config = endpoint.config(:phoenix_profiler)

    link_base =
      case Keyword.fetch(config, :profiler_link_base) do
        {:ok, path} when is_binary(path) and path != "" ->
          "/" <> String.trim_leading(path, "/")

        _ ->
          @default_profiler_link_base
      end

    if conn.private.phoenix_profiler_info == :enable do
      time = System.system_time()

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

      profiler_base_url = endpoint.url() <> link_base

      profile =
        Profile.new(
          conn.private.phoenix_profiler,
          Utils.random_unique_id(),
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
    case apply_profiler_info(conn_or_socket, endpoint) do
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

  defp apply_profiler_info(conn_or_socket, endpoint) do
    endpoint = endpoint || Utils.endpoint(conn_or_socket)

    with {:ok, config} <- Utils.check_configuration(endpoint),
         :ok <- maybe_check_socket_connection(conn_or_socket),
         {:ok, profiler} <- check_profiler_running(config),
         info = if(config[:enable] == false, do: :disable, else: :enable),
         {:ok, collector_pid} <- start_collector(conn_or_socket, profiler, info) do
      {:ok,
       conn_or_socket
       |> Utils.put_private(:phoenix_profiler, profiler)
       |> Utils.put_private(:phoenix_profiler_collector, collector_pid)
       |> Utils.put_private(:phoenix_profiler_info, info)}
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
