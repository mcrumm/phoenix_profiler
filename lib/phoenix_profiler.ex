defmodule PhoenixProfiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @behaviour Plug

  @impl Plug
  defdelegate init(opts), to: PhoenixProfilerWeb.Plug

  @impl Plug
  defdelegate call(conn, opts), to: PhoenixProfilerWeb.Plug

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
  Enables the profiler on a given connected `socket`.

  Normally you do not need to invoke this function. In LiveView 0.16+ it is
  invoked automatically when using `on_mount PhoenixProfiler`.

  Raises if the socket is not connected.

  ## Example

      def mount(params, session, socket) do
        socket =
          if connected?(socket) do
            PhoenixProfiler.enable_live_profiler(socket)
          else
            socket
          end

        # code...

        {:ok, socket}
      end

  """
  defdelegate enable_live_profiler(socket), to: PhoenixProfiler.Utils

  @doc """
  Disables live profiling on a given `socket`.

  ## Examples

      def handle_event("some-event", _, socket) do
        {:noreply, PhoenixProfiler.disable_live_profiler(socket)}
      end

  """
  defdelegate disable_live_profiler(socket), to: PhoenixProfiler.Utils

  @doc """
  Returns a page definition for LiveDashboard.

  To use the profiler dashboard, add it to the
    `:additional_pages` of your live_dashboard:

        live_dashboard "/dashboard",
          additional_pages: [
            _profiler: PhoenixProfiler.dashboard()
            # additional pages...
          ]

  """
  defdelegate dashboard, to: PhoenixProfilerWeb.Dashboard
end
