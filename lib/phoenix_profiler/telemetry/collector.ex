defmodule PhoenixProfiler.TelemetryCollector do
  # @moduledoc """
  # A server to receive telemetry events for profiling/debugging.

  # ## Communications

  # Processes wishing to act as collectors should do the following:

  # First, you invoke `PhoenixProfiler.TelemetryRegistry.register/4`
  # to register the current process as a collector.

  # Then, you will receive messages in the following form:

  #     {:telemetry, register_arg, event_name, event_ts, data}

  # ...with the following values:

  #   * `register_arg` - The `arg` provided to
  #     [`register/4`](`PhoenixProfiler.TelemetryRegistry.register/4`).
  #     Default is `nil`.

  #   * `event_name` - The event name from `:telemetry`.

  #   * `event_ts` - The timestamp as provided by the `:system_time`
  #     measurement if it exists, or the system time when the event
  #     was collected.

  #   * `data` - The data returned by the `filter` provided to the
  #     TelemetryServer. Default is an empty map.

  # ### Examples

  #     iex> start_supervised!({PhoenixProfiler, name: :debug_me, telemetry: [[:debug, :me]]})
  #     iex> {:ok, _} = PhoenixProfiler.TelemetryRegistry.register(:debug_me, self())
  #     iex> :telemetry.execute([:debug, :me], %{}, %{})
  #     iex> receive do
  #     ...>  {:telemetry, nil, [:debug, :me], _, _} ->
  #     ...>    :ok
  #     ...> after
  #     ...>  0 -> raise "telemetry not executed!"
  #     ...>end
  #     :ok

  # """
  @moduledoc false

  use GenServer
  alias PhoenixProfiler.TelemetryRegistry
  alias PhoenixProfiler.Utils

  @doc """
  Disables a given `collector`.

  Disabled collectors will not receive telemetry events.
  """
  def disable(collector), do: GenServer.call(collector, {__MODULE__, :disable})

  @doc """
  Enables a given `collector`.
  """
  def enable(collector), do: GenServer.call(collector, {__MODULE__, :enable})

  @doc """
  Starts a collector linked to the current process.

  ## Examples

      iex> start_supervised!({PhoenixProfiler, name: :debug})
      iex> {:ok, _pid} = PhoenixProfiler.TelemetryCollector.start_link({:debug, self()})
      iex> {:error, {:already_registered, _pid}} = PhoenixProfiler.TelemetryCollector.start_link({:debug, self(), :arg})
      iex> {:error, {:already_registered, pid}} = PhoenixProfiler.TelemetryCollector.start_link({:debug, self(), :arg, :disable})
      iex> Process.alive?(pid)
      true

  """
  def start_link({server, pid}) when is_pid(pid) do
    start_link({server, pid, nil, :enable})
  end

  def start_link({server, pid, arg}) when is_pid(pid) do
    start_link({server, pid, arg, :enable})
  end

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  @doc """
  Reduce over the currently stored events.

  Reduces over the currently stored events and applies a
  function for each event.

  ## Examples

      PhoenixProfiler.TelemetryCollector.reduce(pid, [], &[&1 | &2])

  """
  def reduce(pid, initial, func) when is_function(func, 2) do
    GenServer.call(pid, {:reduce, initial, func})
  end

  @impl GenServer
  def init({server, pid, arg, info}) do
    case TelemetryRegistry.register(server, pid, {self(), arg}, info) do
      {:ok, _} -> {:ok, %{pid: pid, queue: :queue.new()}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:reduce, initial, func}, _from, %{queue: q} = state) do
    {:reply, Utils.queue_fold(func, initial, q), state}
  end

  @impl GenServer
  def handle_call({__MODULE__, action}, _from, %{pid: pid} = state)
      when action in [:disable, :enable] do
    _ = TelemetryRegistry.update_info(pid, fn _ -> action end)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(
        {:telemetry, {pid, _}, _, _, _} = event,
        %{queue: q} = state
      )
      when pid == self() do
    {:noreply, %{state | queue: :queue.in(event, q)}}
  end
end
