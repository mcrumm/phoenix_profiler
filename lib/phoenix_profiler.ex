defmodule PhoenixProfiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  defmacro __using__(_) do
    quote do
      unquote(plug())

      @before_compile PhoenixProfiler.Endpoint
    end
  end

  defp plug do
    # todo: ensure we are within a Phoenix.Endpoint
    quote location: :keep do
      plug PhoenixProfiler.Plug
    end
  end

  @doc """
  Returns the child specification to start the profiler
  under a supervision tree.
  """
  def child_spec(opts) do
    %{
      id: opts[:name] || PhoenixProfiler,
      start: {PhoenixProfiler.Profiler, :start_link, [opts]}
    }
  end

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
    {:cont, PhoenixProfiler.Utils.maybe_mount_profiler(socket)}
  end

  @doc """
  Enables the profiler on a given `conn` or connected `socket`.

  Useful when choosing to start a profiler with
  `[enable: false]`, but normally you do not need to invoke it
  manually.

  Note the profiler server must be running and the `conn` or
  `socket` must have been configured for profiling for this
  function to have any effect.

  ## Example

  Within a Phoenix Controller (for example on a `show` callback):

      def show(conn, params) do
        conn = PhoenixProfiler.enable(conn)
        # code...
      end

  Within a LiveView (for example on a `handle_info` callback):

      def handle_info(:debug_me, socket) do
        socket = PhoenixProfiler.enable(socket)
        # code...
      end

  """
  defdelegate enable(conn_or_socket), to: PhoenixProfiler.Profiler

  @doc """
  Disables profiling on a given `conn` or `socket`.

  ## Examples

  Within a Phoenix Controller (for example on an `update` callback):

      def update(conn, params) do
        conn = PhoenixProfiler.disable(conn)
        # code...
      end

  Within in a LiveView (for example on a `handle_event` callback):

      def handle_event("some-event", _, socket) do
        socket = PhoenixProfiler.disable(socket)
        # code...
      end

  Note that for LiveView, you must invoke `disable/1` _after_
  the LiveView has completed its connected mount for this function
  to have any effect.
  """
  defdelegate disable(conn_or_socket), to: PhoenixProfiler.Profiler

  @doc """
  Resets the storage of the given `profiler`.
  """
  defdelegate reset(profiler), to: PhoenixProfiler.ProfileStore

  @doc """
  Returns all running PhoenixProfiler names.
  It is important to notice that no order is guaranteed.
  """
  def all_running do
    for {{PhoenixProfiler, name}, %PhoenixProfiler.ProfileStore{}} <- :persistent_term.get(),
        GenServer.whereis(name),
        do: name
  end
end
