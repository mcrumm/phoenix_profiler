defmodule PhoenixProfiler.TelemetryRegistry do
  @moduledoc false

  @doc """
  Register the current process as the collector for a given `pid` for `server`.
  """
  def register(server, pid), do: register(server, pid, nil, :enable)
  def register(server, pid, arg), do: register(server, pid, arg, :enable)

  def register(server, pid, arg, info)
      when is_pid(pid) and is_atom(info) and info in [:disable, :enable] do
    Registry.register(__MODULE__, pid, {server, arg, info})
  end

  @doc """
  Updates the status of `pid` for the current process.

  The registry value will be updated to the value returned
  by `func`, a function that accepts the current status and
  must return one of `:enable` or `:disable`.
  """
  def update_info(pid, func) do
    update(pid, fn _, arg, info ->
      case func.(info) do
        :enable -> {arg, :enable}
        :disable -> {arg, :disable}
      end
    end)
  end

  @doc """
  Updates the value for `pid` for the current process.
  """
  def update(pid, func) when is_function(func, 3) do
    Registry.update_value(__MODULE__, pid, fn {server, arg, info} ->
      case func.(server, arg, info) do
        {new_arg, info} when info in [:disable, :enable] ->
          {server, new_arg, info}

        _ ->
          # todo: warn (or raise) on invalid return
          {server, arg, info}
      end
    end)
  end

  @doc """
  Returns the collector for the current process if it exists.

  This function checks the current process and each of its
  callers until it finds a registered collector, then it
  immediately returns `{:ok, {pid, {server, arg, info}}}`,
  otherwise it returns `:error`.

  ## Examples

      PhoenixProfiler.TelemetryRegistry.lookup(:my_profiler)

  """
  def lookup(server) do
    lookup(server, [self() | Process.get(:"$callers", [])])
  end

  defp lookup(server, callers) do
    Enum.reduce_while(callers, :error, fn caller, acc ->
      case Registry.lookup(__MODULE__, caller) do
        [{_, {^server, _, _}} = collector] -> {:halt, {:ok, collector}}
        _ -> {:cont, acc}
      end
    end)
  end
end
