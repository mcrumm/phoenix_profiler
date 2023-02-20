defmodule PhoenixProfiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @behaviour Plug

  @impl Plug
  defdelegate init(opts), to: PhoenixProfiler.Plug

  @impl Plug
  defdelegate call(conn, opts), to: PhoenixProfiler.Plug

  # TODO: Remove when we require LiveView v0.17+.
  @doc false
  def mount(params, session, socket) do
    on_mount(:default, params, session, socket)
  end

  @doc """
  The callback for the mount stage of the LiveView lifecycle.

  To enable live profiling, add the following on your LiveView:

      on_mount PhoenixProfiler

  """
  def on_mount(_arg, _params, _session, socket) do
    {:cont, PhoenixProfiler.Utils.maybe_mount_profile(socket)}
  end

  @doc """
  Enables the profiler on a given `conn` or connected `socket`.

  Normally you do not need to invoke this function manually. It is invoked
  automatically by the PhoenixProfiler plug in the Endpoint when a
  profiler is enabled. In LiveView v0.16+ it is invoked automatically when
  you define `on_mount PhoenixProfiler` on your LiveView.

  This function raises if the endpoint is not configured with `:phoenix_profiler`.
  For LiveView, this function also raises if the given socket is not connected.

  ## Example

  Within a Phoenix Controller (for example, on a show callback):

      def show(conn, params) do
        conn = PhoenixProfiler.enable(conn)
        # code...
      end

  Within a LiveView (for example, on the mount callback):

      def mount(params, session, socket) do
        socket =
          if connected?(socket) do
            PhoenixProfiler.enable(socket)
          else
            socket
          end

        # code...
      end

  """
  defdelegate enable(conn_or_socket), to: PhoenixProfiler.Utils, as: :enable_profiler

  @doc """
  Disables profiling on a given `conn` or `socket`.

  ## Examples

  Within a Phoenix Controller (for example, on an update callback):

      def update(conn, params) do
        conn = PhoenixProfiler.disable(conn)
        # code...
      end

  Within in a LiveView (for example, on a handle_event callback):

      def handle_event("some-event", _, socket) do
        socket = PhoenixProfiler.disable(socket)
        # code...
      end

  Note that only for LiveView, if you invoke `disable/1` on
  the LiveView `mount` callback, the profiler may not be
  registered yet and it will not receive the disable message.
  If you need on-demand profiling, it is recommended you
  start with the profiler in a disabled state and enable it
  after the LiveView has mounted.
  """
  defdelegate disable(conn_or_socket), to: PhoenixProfiler.Utils, as: :disable_profiler

  @doc """
  Resets the storage of the given `profiler`.
  """
  defdelegate reset, to: PhoenixProfiler.Server

  @doc """
  Returns system-level data collected by the profiler at start.
  """
  def system do
    case :persistent_term.get(PhoenixProfiler) do
      %{system: %{} = system} -> system
      _ -> nil
    end
  end

  @doc """
  Returns a list of known endpoints.

  It is important to note that the order is not guaranteed.
  """
  def known_endpoints do
    for {{PhoenixProfiler.Endpoint, endpoint}, _} <- :persistent_term.get() do
      endpoint
    end
  end
end
