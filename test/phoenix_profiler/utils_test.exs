defmodule PhoenixProfiler.UtilsTest do
  use ExUnit.Case
  alias Phoenix.LiveView

  defp build_socket(endpoint \\ PhoenixProfilerTest.Endpoint) do
    %LiveView.Socket{endpoint: endpoint}
  end

  defp connect(%LiveView.Socket{} = socket) do
    # TODO: replace with struct update when we require LiveView v0.15+.
    socket = Map.put(socket, :transport_pid, self())

    # TODO: remove when we require LiveView v0.15+.
    if Map.has_key?(socket, :connected?) do
      Map.put(socket, :connected?, true)
    else
      socket
    end
  end

  describe "maybe_mount_profile1/" do
    test "when the socket is disconnected, is a no-op" do
      socket = build_socket()
      refute socket.private[:phoenix_profiler]
      assert PhoenixProfiler.Utils.maybe_mount_profile(socket) == socket
    end

    test "when the profiler is enabled on the endpoint, configures an enabled profile" do
      socket = build_socket() |> connect() |> PhoenixProfiler.Utils.maybe_mount_profile()
      assert %PhoenixProfiler.Profile{info: :enable} = socket.private.phoenix_profiler
    end

    test "when the profiler is disabled on the endpoint, configures a disabled profile" do
      socket =
        PhoenixProfilerTest.EndpointDisabled
        |> build_socket()
        |> connect()
        |> PhoenixProfiler.Utils.maybe_mount_profile()

      assert %PhoenixProfiler.Profile{info: :disable} = socket.private.phoenix_profiler
    end

    test "when the profiler is not defined on the endpoint, is a no-op" do
      socket = PhoenixProfilerTest.EndpointNotConfigured |> build_socket() |> connect()
      assert PhoenixProfiler.Utils.maybe_mount_profile(socket) == socket
    end
  end
end
