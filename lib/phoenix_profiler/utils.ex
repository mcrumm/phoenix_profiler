defmodule PhoenixProfiler.Utils do
  @moduledoc false
  alias Phoenix.LiveView

  @doc """
  Enables the live profiler on a given connected `socket`.

  Raises if the socket is not connected.
  """
  def enable_live_profiler(%LiveView.Socket{} = socket) do
    unless LiveView.connected?(socket) do
      raise """
      attempted to enable live profiling on a disconnected socket

      In your LiveView mount callback, do the following:

          socket =
            if connected?(socket) do
              PhoenixProfiler.enable_live_profiler(socket)
            else
              socket
            end

      """
    end

    profile_key = {socket.view, make_ref()}
    put_private(socket, :phxprof_enabled, profile_key)
  end

  @doc """
  Disables the live profiler on a given `socket`.
  """
  def disable_live_profiler(%LiveView.Socket{} = socket) do
    put_private(socket, :phxprof_enabled, false)
  end

  @doc """
  Assigns a new private key and value in the socket.
  """
  def put_private(%LiveView.Socket{} = socket, key, value) when is_atom(key) do
    private = Map.put(socket.private, key, value)
    %{socket | private: private}
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
end
