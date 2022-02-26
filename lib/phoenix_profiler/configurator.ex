defmodule PhoenixProfiler.Configurator do
  @moduledoc false
  alias Phoenix.LiveView
  alias PhoenixProfiler.TelemetryServer
  alias PhoenixProfiler.Utils

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

  defp update_info(conn_or_socket, action) when action in [:disable, :enable] do
    TelemetryServer.collector_info_exec(action)
    Utils.put_private(conn_or_socket, :phoenix_profiler_info, action)
  end

  @doc """
  Configures profiling for a given `conn` or `socket`.
  """
  def configure(conn_or_socket) do
    case apply_profiler_info(conn_or_socket) do
      {:ok, conn_or_socket} ->
        {:ok, conn_or_socket}

      {:error, :profiler_not_available} ->
        {:error, :profiler_not_available}

      {:error, reason} ->
        configure_profile_error(conn_or_socket, :configure, reason)
    end
  end

  defp apply_profiler_info(conn_or_socket) do
    endpoint = Utils.endpoint(conn_or_socket)

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
