defmodule PhoenixProfiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @doc """
  Returns the child specification to start the profiler
  under a supervision tree.
  """
  def child_spec(opts) do
    name = opts[:name] || raise ArgumentError, ":name is required to start the profiler"

    %{
      id: name,
      start: {PhoenixProfiler.Profiler, :start_link, [{name, opts}]}
    }
  end

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
  Enables the profiler on a given `conn` or connected `socket`.

  Normally you do not need to invoke this function manually. It is invoked
  automatically by the PhoenixProfiler plug in the Endpoint when a
  profiler is enabled. In LiveView v0.16+ it is invoked automatically when
  you define `on_mount PhoenixProfiler` on your LiveView.

  This function will raise if the endpoint is not configured with a profiler,
  or if the configured profiler is not running. For LiveView specifically,
  this function also raises if the given socket is not connected.

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

  """
  defdelegate disable(conn_or_socket), to: PhoenixProfiler.Utils, as: :disable_profiler

  @doc """
  Resets the storage of the given `profiler`.
  """
  defdelegate reset(profiler), to: PhoenixProfiler.Profiler

  @doc """
  Returns all running PhoenixProfiler names.
  It is important to notice that no order is guaranteed.
  """
  def all_running do
    for {{PhoenixProfiler, name}, %PhoenixProfiler.Profiler{}} <- :persistent_term.get(),
        GenServer.whereis(name),
        do: name
  end
end
