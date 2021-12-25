defmodule PhoenixProfiler.Profiler do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.Utils

  defstruct [:tab]

  @doc """
  Resets the profiler, deleting all stored requests.
  """
  @callback reset :: :ok

  @default_sweep_interval :timer.minutes(1)

  defmacro __using__(opts) do
    quote do
      @otp_app unquote(opts)[:otp_app]

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {PhoenixProfiler.Profiler, :start_link, [{__MODULE__, opts}]}
        }
      end

      def reset do
        PhoenixProfiler.Profiler.reset(__MODULE__)
      end

      def config do
        case Application.get_env(@otp_app, __MODULE__) do
          config when is_list(config) -> config
          _ -> []
        end
      end
    end
  end

  def start_link({module, opts}) do
    GenServer.start_link(__MODULE__, {module, opts}, name: module)
  end

  def reset(module) do
    if tab = table(module) do
      :ets.delete_all_objects(tab)
      :ok
    end
  end

  def init({module, opts}) do
    options = Keyword.merge(module.config(), opts)

    tab = :ets.new(module, [:set, :public, {:write_concurrency, true}])
    :persistent_term.put({PhoenixProfiler, module}, %__MODULE__{tab: tab})

    :telemetry.attach_many(
      {PhoenixProfiler, module, self()},
      [
        [:phoenix, :endpoint, :stop],
        [:phxprof, :plug, :stop]
      ],
      &__MODULE__.telemetry_callback/4,
      {module, tab}
    )

    request_sweep_interval = options[:request_sweep_interval] || @default_sweep_interval
    schedule_sweep(module, request_sweep_interval)

    {:ok,
     %{
       server: module,
       requests: tab,
       request_sweep_interval: request_sweep_interval
     }}
  end

  def handle_info(:sweep, state) do
    schedule_sweep(state.server, state.request_sweep_interval)
    :ets.delete_all_objects(state.requests)
    {:noreply, state}
  end

  def profiler(%Plug.Conn{} = conn) do
    case conn.private[:phoenix_profiler] do
      %Profile{server: server} when is_atom(server) -> server
      nil -> nil
    end
  end

  def get(profiler, token) do
    case :ets.lookup(table(profiler), token) do
      [] ->
        nil

      [{_token, profile}] ->
        profile
    end
  end

  def list(profiler) do
    :ets.tab2list(table(profiler))
  end

  def list_advanced(profiler, _search, sort_by, sort_dir, _limit) do
    Utils.sort_by(list(profiler), fn {_, profile} -> profile[sort_by] end, sort_dir)
  end

  def remote_get(%Profile{} = profile) do
    remote_get(profile.node, profile.server, profile.token)
  end

  def remote_get(node, profiler, token) do
    :rpc.call(node, __MODULE__, :get, [profiler, token])
  end

  def remote_list_advanced(node, profiler, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :list_advanced, [profiler, search, sort_by, sort_dir, limit])
  end

  defp table(profiler) do
    case :persistent_term.get({PhoenixProfiler, profiler}) do
      %__MODULE__{tab: tab} -> tab
      _ -> nil
    end
  end

  def telemetry_callback([:phoenix, :endpoint, :stop], %{duration: duration}, _meta, _context) do
    Process.put(:phxprof_endpoint_duration, duration)
  end

  def telemetry_callback(
        [:phxprof, :plug, :stop],
        measurements,
        %{conn: %{private: %{phoenix_profiler: %Profile{server: profiler}}} = conn},
        {profiler, table}
      ) do
    profile = conn.private.phoenix_profiler

    case profile.info do
      :enable ->
        collect_and_insert_profile(conn, profile, measurements, table)
        :ok

      :disable ->
        :ok

      nil ->
        :ok
    end
  end

  def telemetry_callback([:phxprof, :plug, :stop], _, _, _), do: :ok

  defp collect_and_insert_profile(%Plug.Conn{} = conn, %Profile{} = profile, measurements, table) do
    # Measurements
    {:memory, bytes} = Process.info(conn.owner, :memory)
    memory = div(bytes, 1_024)

    data = %{
      at: profile.system_time,
      conn: %{conn | resp_body: nil, assigns: Map.delete(conn.assigns, :content)},
      metrics: %{
        endpoint_duration: Process.get(:phxprof_endpoint_duration),
        memory: memory,
        total_duration: measurements.duration
      }
    }

    :ets.insert(table, {profile.token, data})
  end

  defp schedule_sweep(module, time) do
    Process.send_after(module, :sweep, time)
  end
end
