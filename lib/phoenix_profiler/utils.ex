defmodule PhoenixProfiler.Utils do
  @moduledoc false
  alias Phoenix.LiveView

  @doc """
  Returns info for `server` about the registered collector for a given `conn` or `socket`.
  """
  def collector_info(server, conn_or_socket) do
    case Registry.lookup(PhoenixProfiler.TelemetryRegistry, target_pid(conn_or_socket)) do
      [{pid, {^server, {pid, nil}, info}}] when is_pid(pid) -> {info, pid}
      [] -> :error
    end
  end

  @doc """
  Returns the pid to target when collecting data.
  """
  def target_pid(conn_or_socket)
  def target_pid(%Plug.Conn{owner: owner}), do: owner
  def target_pid(%LiveView.Socket{} = socket), do: transport_pid(socket)

  @doc """
  Returns the endpoint for a given `conn` or `socket`.
  """
  def endpoint(conn_or_socket)
  def endpoint(%Plug.Conn{} = conn), do: conn.private.phoenix_endpoint
  def endpoint(%LiveView.Socket{endpoint: endpoint}), do: endpoint

  @doc """
  Checks whether or not a configuration exists.
  """
  def check_configuration(endpoint) when is_atom(endpoint) do
    case endpoint.config(:phoenix_profiler) do
      [_ | _] = config -> {:ok, config}
      _ -> {:error, :profiler_not_available}
    end
  end

  def check_configuration(%_{} = struct) do
    struct |> endpoint() |> check_configuration()
  end

  @doc """
  Checks whether or not a socket is connected.
  """
  @spec check_socket_connection(socket :: LiveView.Socket.t()) ::
          :ok | {:error, :waiting_for_connection}
  def check_socket_connection(%LiveView.Socket{} = socket) do
    if LiveView.connected?(socket) do
      :ok
    else
      {:error, :waiting_for_connection}
    end
  end

  @doc """
  Assigns a new private key and value in the socket.
  """
  def put_private(%Plug.Conn{} = conn, key, value) when is_atom(key) do
    Plug.Conn.put_private(conn, key, value)
  end

  def put_private(%LiveView.Socket{private: private} = socket, key, value) when is_atom(key) do
    %{socket | private: Map.put(private, key, value)}
  end

  # Unique ID generation
  # Copyright (c) 2013 Plataformatec.
  # https://github.com/elixir-plug/plug/blob/fb6b952cf93336dc79ec8d033e09a424d522ce56/lib/plug/request_id.ex
  @doc false
  def random_unique_id do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end

  @doc """
  Returns a map of system version metadata.
  """
  def system do
    for app <- [:otp, :elixir, :phoenix, :phoenix_live_view, :phoenix_profiler], into: %{} do
      {app, version(app)}
    end
  end

  defp version(:elixir), do: System.version()
  defp version(:otp), do: System.otp_release()

  defp version(app) when is_atom(app) do
    Application.spec(app)[:vsn]
  end

  @doc """
  Returns the `transport_pid` for a given `socket`.
  """
  # TODO: replace with `socket.transport_pid` when we require LiveView v0.16+.
  def transport_pid(%LiveView.Socket{} = socket) do
    Map.get_lazy(socket, :transport_pid, fn ->
      LiveView.transport_pid(socket)
    end)
  end

  @doc false
  def sort_by(enumerable, sort_by_fun, :asc) do
    Enum.sort_by(enumerable, sort_by_fun, &<=/2)
  end

  def sort_by(enumerable, sort_by_fun, :desc) do
    Enum.sort_by(enumerable, sort_by_fun, &>=/2)
  end

  # backwards compability
  if Version.match?(System.version(), ">= 1.10.0") do
    defdelegate map_pop!(map, key), to: Map, as: :pop!
  else
    # https://github.com/elixir-lang/elixir/blob/e29f1492a48c53ff41b4d60b6a7b5307692145f6/lib/elixir/lib/map.ex#L734
    def map_pop!(map, key) do
      case :maps.take(key, map) do
        {_, _} = tuple -> tuple
        :error -> raise KeyError, key: key, term: map
      end
    end
  end

  if String.to_integer(System.otp_release()) >= '24' do
    defdelegate queue_fold(func, initial, queue), to: :queue, as: :fold
  else
    # https://github.com/erlang/otp/blob/9f87c568cd3cdb621cf4cae69ccce880be4ea1b6/lib/stdlib/src/queue.erl#L442
    def queue_fold(func, initial, {r, f})
        when is_function(func, 2) and is_list(r) and is_list(f) do
      acc = :lists.foldl(func, initial, f)
      :lists.foldr(func, acc, r)
    end
  end
end
