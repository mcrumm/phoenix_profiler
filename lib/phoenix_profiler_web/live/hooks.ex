defmodule PhoenixProfilerWeb.Hooks do
  # LiveView lifecycle hooks for on-demand profiling.
  @moduledoc false
  alias Phoenix.LiveView
  alias PhoenixProfiler.Utils

  # TODO: Remove when we support only LiveView 0.17+
  def mount(params, session, socket) do
    on_mount(:default, params, session, socket)
  end

  def on_mount(_arg, _params, _session, socket) do
    if LiveView.connected?(socket) do
      {:cont, Utils.enable_live_profiler(socket)}
    else
      {:cont, socket}
    end
  end
end
