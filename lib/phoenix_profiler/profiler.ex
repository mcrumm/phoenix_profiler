defmodule PhoenixProfiler.Profiler do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.Utils

  defstruct [:tab]

  defmacro __using__(opts) do
    quote do
      @otp_app unquote(opts)[:otp_app]

      def child_spec(_) do
        %{
          id: __MODULE__,
          start: {PhoenixProfiler.Profiler, :start_link, [__MODULE__]}
        }
      end
    end
  end

  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: module)
  end

  def init(module) do
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

    {:ok, %{profiler: module, requests: tab}}
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

      [{_token, value}] ->
        value
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
    %__MODULE__{tab: tab} = :persistent_term.get({PhoenixProfiler, profiler})
    tab
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
end
