defmodule PhoenixProfiler.ProfileStore do
  # GenServer that is the owner of the ETS table for requests
  @moduledoc false
  use GenServer
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.Utils

  defstruct [:tab, :system]

  @doc """
  Resets the profiler, deleting all stored requests.
  """
  @callback reset :: :ok

  @default_sweep_interval :timer.hours(24)

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  @doc """
  Deletes all objects in the profiler table.
  """
  def reset(name) do
    if tab = tab(name) do
      :ets.delete_all_objects(tab)
      :ok
    end
  end

  @doc """
  Returns system-level data collected by the profiler at start.
  """
  def system(name) do
    case :persistent_term.get({PhoenixProfiler, name}) do
      %__MODULE__{system: system} -> system
      _ -> nil
    end
  end

  @impl GenServer
  def init({server, options}) do
    system = Utils.system()
    tab = :ets.new(server, [:set, :public, {:write_concurrency, true}])

    :persistent_term.put({PhoenixProfiler, server}, %__MODULE__{
      system: system,
      tab: tab
    })

    request_sweep_interval = options[:request_sweep_interval] || @default_sweep_interval
    schedule_sweep(self(), request_sweep_interval)

    {:ok,
     %{
       server: server,
       requests: tab,
       request_sweep_interval: request_sweep_interval
     }}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    schedule_sweep(self(), state.request_sweep_interval)
    :ets.delete_all_objects(state.requests)
    {:noreply, state}
  end

  @doc """
  Returns the profiler for a given `conn` if it exists.
  """
  def profiler(%Plug.Conn{} = conn) do
    case conn.private[:phoenix_profiler] do
      %Profile{server: server} -> server
      nil -> nil
    end
  end

  @doc """
  Returns the profiler for a given `profiler` and a given `token` if it exists.
  """
  def get(profiler, token) do
    case :ets.lookup(tab(profiler), token) do
      [] ->
        nil

      [{_token, profile}] ->
        profile
    end
  end

  @doc """
  Returns all profiles for a given `profiler`.
  """
  def list(profiler) do
    :ets.tab2list(tab(profiler))
  end

  @doc """
  Returns a filtered list of profiles.
  """
  def list_advanced(profiler, _search, :at, sort_dir, limit) do
    results = Utils.sort_by(list(profiler), fn {_, %Profile{} = p} -> p.system_time end, sort_dir)

    {Enum.take(results, limit), length(results)}
  end

  def list_advanced(profiler, _search, sort_by, sort_dir, limit) do
    results =
      Utils.sort_by(list(profiler), fn {_, %Profile{} = p} -> p.data[sort_by] end, sort_dir)

    {Enum.take(results, limit), length(results)}
  end

  @doc """
  Fetches a profile on a remote node.
  """
  def remote_get(node, profiler, token) do
    :rpc.call(node, __MODULE__, :get, [profiler, token])
  end

  @doc """
  Returns a filtered list of profiles on a remote node.
  """
  def remote_list_advanced(node, profiler, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :list_advanced, [profiler, search, sort_by, sort_dir, limit])
  end

  @doc """
  Returns the ETS table for a given `profile`.
  """
  def table(%Profile{server: profiler} = _profile) do
    tab(profiler)
  end

  defp tab(profiler) do
    case :persistent_term.get({PhoenixProfiler, profiler}) do
      %__MODULE__{tab: tab} -> tab
      _ -> nil
    end
  end

  defp schedule_sweep(server, time) do
    Process.send_after(server, :sweep, time)
  end
end
