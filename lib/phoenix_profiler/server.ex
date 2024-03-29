defmodule PhoenixProfiler.Server do
  @moduledoc false
  use GenServer

  @endpoint_table __MODULE__.Endpoint
  @listener_table __MODULE__.Listener
  @live_table __MODULE__.Live
  @entry_table __MODULE__.Entry

  @default_sweep_interval :timer.hours(24)

  @disable_key :phoenix_profiler_disable
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
  Update the profiling status of the caller.

  Returns the previous status, or `nil` if the status was not yet set.
  """
  def profiling(status) when is_boolean(status) do
    Process.put(@disable_key, not status)
  end

  @doc """
  Returns whether or not profiling is enabled for the current process.
  """
  def profiling? do
    if Process.get(@disable_key), do: false, else: true
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
  Makes the caller observable by listeners.
  """
  @spec make_observable(owner :: pid(), endpoint :: atom()) :: {:ok, token :: String.t()}
  def make_observable(owner \\ self(), endpoint) when is_pid(owner) and is_atom(endpoint) do
    token =
      case fetch_owner_token(owner) do
        {:ok, token} ->
          token

        :error ->
          token = PhoenixProfiler.Utils.random_unique_id()
          :persistent_term.put({PhoenixProfiler.Endpoint, endpoint}, nil)
          true = :ets.insert(@endpoint_table, {endpoint, token})
          true = :ets.insert(@live_table, {owner, token})
          GenServer.cast(__MODULE__, {:monitor, owner})
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
  Deletes all objects in the entry tables.
  """
  def reset do
    :ets.delete_all_objects(@entry_table)
    :ets.delete_all_objects(@endpoint_table)
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

  @impl true
  def handle_cast({:monitor, owner}, state) do
    _ = Process.monitor(owner)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    schedule_sweep(state.request_sweep_interval)
    reset()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _, _, owner, _}, state) do
    case :ets.lookup(@live_table, owner) do
      [{^owner, token}] ->
        :ets.delete(@live_table, owner)
        :ets.delete(@listener_table, token)

      [] ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def init(%{events: events, filter: filter}) do
    Process.flag(:trap_exit, true)

    :persistent_term.put(PhoenixProfiler, %{system: PhoenixProfiler.Utils.system()})
    :ets.new(@endpoint_table, [:named_table, :public, :bag])
    :ets.new(@live_table, [:named_table, :public, :set])
    :ets.new(@listener_table, [:named_table, :public, :bag])
    :ets.new(@entry_table, [:named_table, :public, :duplicate_bag])

    :telemetry.attach_many(
      {__MODULE__, self()},
      events,
      &__MODULE__.handle_execute/4,
      %{filter: filter}
    )

    request_sweep_interval =
      Application.get_env(:phoenix_profiler, :request_sweep_interval, @default_sweep_interval)

    schedule_sweep(request_sweep_interval)

    {:ok, %{request_sweep_interval: request_sweep_interval}}
  end

  @doc """
  Forwards telemetry events to subscribed listeners.
  """
  def handle_execute(event, measurements, metadata, %{filter: filter}) do
    # capture system_time early in case we need it
    system_time = System.system_time()

    with true <- profiling?(),
         {:ok, token} <- find_token(),
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
