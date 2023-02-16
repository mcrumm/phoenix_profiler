defmodule PhoenixProfiler.Server do
  @moduledoc false
  use GenServer

  @disable_event [:phoenix_profiler, :internal, :collector, :disable]
  @enable_event [:phoenix_profiler, :internal, :collector, :enable]

  @disable_table __MODULE__.Disable
  @endpoint_table __MODULE__.Endpoint
  @listener_table __MODULE__.Listener
  @live_table __MODULE__.Live
  @entry_table __MODULE__.Entry

  @default_sweep_interval :timer.hours(24)

  @process_dict_key :phoenix_profiler_token

  @doc """
  Returns the profile token for the current process if it exists.

  This function checks the current process and each of its callers
  until it finds a token, then it immediately returns `{:ok, token}`,
  otherwise it returns `:error`.

  ## Examples

      PhoenixProfiler.Server.find_token()

  """
  def find_token do
    callers = [self() | Process.get(:"$callers", [])]

    Enum.reduce_while(callers, :error, fn caller, acc ->
      case Process.info(caller, :dictionary) do
        {:dictionary, dict} ->
          if token = dict[@process_dict_key] do
            {:halt, {:ok, token}}
          else
            {:cont, acc}
          end

        nil ->
          {:cont, acc}
      end
    end)
  end

  @doc """
  Returns a list of known endpoints.

  It is important to note that the order is not guaranteed.
  """
  def known_endpoints do
    for {{PhoenixProfiler.Endpoint, endpoint}, _} <- :persistent_term.get() do
      endpoint
    end
  end

  @doc """
  Subscribes the caller to events for the given `owner` pid.

  While subscribed, you will receive messages in the following form:

      {PhoenixProfiler.Server, token, {:telemetry, event_name, system_time, data}}

  ...with the following values:

   * `token` - The profiler token returned when the caller subscribes.

   * `event_name` - The event name from `:telemetry`.

   * `system_time` - The timestamp as provided by the `:system_time`
     measurement if it exists, or the system time when the event
     was collected.

   * `data` - The data returned by the filter provided to the
     TelemetryServer. The default value is an empty map `%{}`.
  """
  @spec subscribe(owner :: pid()) :: {:ok, token :: String.t()} | :error
  def subscribe(owner) when is_pid(owner) do
    with {:ok, token} <- fetch_owner_token(owner) do
      :ets.insert_new(@listener_table, {token, self()})
      {:ok, token}
    end
  end

  @doc """
  Unsubscribes the caller from events for the given `token`.
  """
  def unsubscribe(token) do
    :ets.delete_object(@listener_table, {token, self()})
  end

  @doc """
  Returns a list of entries for a given `token`.
  """
  def lookup_entries(token) do
    :ets.lookup(@entry_table, token)
  end

  @doc """
  Puts the profiler token on the process dictionary.
  """
  @spec put_owner_token(owner :: pid(), endpoint :: atom()) :: {:ok, token :: String.t()}
  def put_owner_token(owner \\ self(), endpoint) when is_pid(owner) and is_atom(endpoint) do
    token =
      case fetch_owner_token(owner) do
        {:ok, token} ->
          token

        :error ->
          token = PhoenixProfiler.Utils.random_unique_id()
          :persistent_term.put({PhoenixProfiler.Endpoint, endpoint}, nil)
          true = :ets.insert(@endpoint_table, {endpoint, token})
          true = :ets.insert(@live_table, {owner, token})
          # todo: GenServer.cast(__MODULE__, {:monitor, owner})
          token
      end

    Process.put(@process_dict_key, token)

    {:ok, token}
  end

  defp fetch_owner_token(owner) do
    case :ets.lookup(@live_table, owner) do
      [{^owner, token}] -> {:ok, token}
      [] -> :error
    end
  end

  @doc """
  Deletes all objects in the profiler table.
  """
  def reset do
    :ets.delete_all_objects(@entry_table)
    :ok
  end

  @doc """
  Starts a telemetry server linked to the current process.
  """
  def start_link(_opts) do
    config = %{
      filter: &PhoenixProfiler.Telemetry.collect/4,
      events: PhoenixProfiler.Telemetry.events()
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Executes the collector event for the given `profile`.
  """
  def collector_info_exec(%PhoenixProfiler.Profile{} = profile) do
    event =
      case profile.info do
        :enable -> @enable_event
        :disable -> @disable_event
      end

    :telemetry.execute(event, %{system_time: System.system_time()}, %{profile: profile})
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    schedule_sweep(state.request_sweep_interval)
    :ets.delete_all_objects(@entry_table)
    {:noreply, state}
  end

  @impl true
  def init(%{events: events, filter: filter}) do
    Process.flag(:trap_exit, true)

    :persistent_term.put(PhoenixProfiler, %{system: PhoenixProfiler.Utils.system()})
    :ets.new(@disable_table, [:named_table, :public, :set])
    :ets.new(@endpoint_table, [:named_table, :public, :bag])
    :ets.new(@live_table, [:named_table, :public, :set])
    :ets.new(@listener_table, [:named_table, :public, :bag])
    :ets.new(@entry_table, [:named_table, :public, :duplicate_bag])

    :telemetry.attach_many(
      {__MODULE__, self()},
      events ++ [@disable_event, @enable_event],
      &__MODULE__.handle_execute/4,
      %{filter: filter}
    )

    request_sweep_interval =
      Application.get_env(:phoenix_profiler, :request_sweep_interval, @default_sweep_interval)

    schedule_sweep(request_sweep_interval)

    {:ok, %{request_sweep_interval: request_sweep_interval}}
  end

  @doc """
  Forwards telemetry events to a registered collector, if it exists.
  """
  def handle_execute(@enable_event, _, %{profile: profile}, _) do
    :ets.delete(@disable_table, profile.token)
    :ok
  end

  def handle_execute(@disable_event, _, %{profile: profile}, _) do
    :ets.insert_new(@disable_table, {profile.token, self()})
    :ok
  end

  def handle_execute(event, measurements, metadata, %{filter: filter}) do
    # capture system_time early in case we need it
    system_time = System.system_time()

    with {:ok, token} <- find_token(),
         [] <- :ets.lookup(@disable_table, token),
         {:keep, data} <- filter_event(filter, _arg = nil, event, measurements, metadata) do
      # todo: ensure span ref is set on data (or message) if it exists
      event_ts = measurements[:system_time] || system_time
      true = :ets.insert(@entry_table, {token, event, event_ts, data})
      notify_subscribers(token, event, event_ts, data)
    else
      _ -> :ok
    end
  end

  defp filter_event(filter, arg, event, measurements, metadata) do
    # todo: rescue/catch, detach telemetry, and warn on error
    case filter.(arg, event, measurements, metadata) do
      :keep -> {:keep, nil}
      {:keep, %{}} = keep -> keep
      :skip -> :skip
    end
  end

  defp notify_subscribers(token, event, event_ts, data) do
    subscribers = :ets.lookup(@listener_table, token)

    Enum.each(subscribers, fn {_, pid} ->
      send(pid, {__MODULE__, token, {:telemetry, event, event_ts, data}})
    end)
  end

  defp schedule_sweep(server \\ self(), time) do
    Process.send_after(server, :sweep, time)
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach({__MODULE__, self()})
    :ok
  end
end
