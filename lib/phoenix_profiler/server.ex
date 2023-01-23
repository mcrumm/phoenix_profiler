defmodule PhoenixProfiler.Server do
  @moduledoc false
  use GenServer

  @disable_event [:phoenix_profiler, :internal, :collector, :disable]
  @enable_event [:phoenix_profiler, :internal, :collector, :enable]

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
  Returns a list of entries for a given `token`.
  """
  def lookup_entries(token) do
    :ets.lookup(@entry_table, token)
  end

  @doc """
  Puts the profiler token on the process dictionary.
  """
  def put_token(%{token: token}) do
    Process.put(@process_dict_key, token)
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
  Executes the collector event for `info` for the current process.
  """
  def collector_info_exec(:disable), do: telemetry_exec(@disable_event)
  def collector_info_exec(:enable), do: telemetry_exec(@enable_event)

  defp telemetry_exec(event) do
    :telemetry.execute(event, %{system_time: System.system_time()}, %{})
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
    :ets.new(@entry_table, [:named_table, :public, :set])

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
  def handle_execute([_, _, _, _info] = event, _, _, _)
      when event in [@disable_event, @enable_event] do
    # todo: handle enable/disable
    :ok
  end

  def handle_execute(event, measurements, metadata, %{filter: filter}) do
    with {:ok, token} <- find_token() do
      # todo: ensure span ref is set on data (or message) if it exists
      data = filter_event(filter, _arg = nil, event, measurements, metadata)
      event_ts = measurements[:system_time] || System.system_time()

      if data do
        :ets.insert(@entry_table, {token, event, event_ts, data})
      end
    end
  end

  defp filter_event(filter, arg, event, measurements, metadata) do
    # todo: rescue/catch, detach telemetry, and warn on error
    case filter.(arg, event, measurements, metadata) do
      :keep -> %{}
      {:keep, data} when is_map(data) -> data
      :skip -> nil
    end
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
