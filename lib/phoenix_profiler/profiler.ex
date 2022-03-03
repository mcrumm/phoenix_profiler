defmodule PhoenixProfiler.Profiler do
  @moduledoc false
  use Supervisor
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfiler.Telemetry
  alias PhoenixProfiler.TelemetryServer
  alias PhoenixProfiler.Utils

  @doc """
  Builds a profile from data collected for a given `conn`.
  """
  def collect(%Profile{info: :enable} = profile, collector_pid) when is_pid(collector_pid) do
    time = System.system_time()

    data =
      PhoenixProfiler.TelemetryCollector.reduce(
        collector_pid,
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

    {:ok, %Profile{profile | data: data, system_time: time}}
  end

  def collect(%Profile{info: :disable}, _) do
    :error
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
  def disable(%{private: %{phoenix_profiler: profile}} = conn_or_socket) do
    :ok = TelemetryServer.disable_key(profile.server, Utils.target_pid(conn_or_socket))
    Utils.put_private(conn_or_socket, :phoenix_profiler, %{profile | info: :disable})
  end

  def disable(conn_or_socket), do: conn_or_socket

  @doc """
  Enables profiling for a given `conn` or `socket`.
  """
  def enable(%{private: %{phoenix_profiler: profile}} = conn_or_socket) do
    :ok = TelemetryServer.enable_key(profile.server, Utils.target_pid(conn_or_socket))
    Utils.put_private(conn_or_socket, :phoenix_profiler, %{profile | info: :enable})
  end

  def enable(conn_or_socket), do: conn_or_socket

  @doc """
  Returns a sparse data structure for a profile.

  Useful mostly for initializing the profile at the beginning of a request.
  """
  def preflight(endpoint) do
    preflight(endpoint, endpoint.config(:phoenix_profiler))
  end

  def preflight(_endpoint, nil), do: :error
  def preflight(endpoint, config), do: preflight(endpoint, config[:server], config)

  defp preflight(endpoint, nil = _server, _config) do
    IO.warn("no profiler server found for endpoint #{inspect(endpoint)}")
    :error
  end

  defp preflight(endpoint, server, config) when is_atom(server) do
    info = if config[:enable] == false, do: :disable, else: :enable
    token = Utils.random_unique_id()
    url = endpoint.url() <> Utils.profile_base_path(config)

    {:ok, Profile.new(endpoint, server, token, url, info)}
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

  @doc """
  Starts a telemetry collector for `conn` for a given `profile`.
  """
  def start_collector(conn, %Profile{} = profile) do
    case TelemetryServer.listen(profile.server, Utils.target_pid(conn), nil, profile.info) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_registered, pid}} ->
        case profile.info do
          :disable -> TelemetryServer.disable_key(profile.server, Utils.target_pid(conn))
          :enable -> TelemetryServer.enable_key(profile.server, Utils.target_pid(conn))
        end

        {:ok, pid}
    end
  end
end
