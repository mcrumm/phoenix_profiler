defmodule PhoenixProfiler do
  alias Phoenix.LiveView
  alias PhoenixProfiler.Utils

  # TODO: Remove when we support only LiveView 0.17+
  @doc false
  defdelegate mount(params, session, socket), to: PhoenixProfilerWeb.Hooks

  @doc """
  The callback for the mount stage of the LiveView lifecycle.

  To enable live profiling, add the following on your LiveView:

      on_mount PhoenixProfiler

  """
  defdelegate on_mount(arg, params, session, socket), to: PhoenixProfilerWeb.Hooks

  @doc """
  Enables the profiler on a given `socket`.

  Normally you do not need to invoke this function. In LiveView 0.16+ it is
  invoked automatically when using `on_mount PhoenixProfiler`.
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
    Utils.put_private(socket, :phxprof_enabled, profile_key)
  end

  @doc """
  Disables the live profiler on a given `socket`.
  """
  def disable_live_profiler(%LiveView.Socket{} = socket) do
    Utils.put_private(socket, :phxprof_enabled, false)
  end
end
