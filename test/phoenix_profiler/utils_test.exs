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

  describe "maybe_mount_profile/1" do
    test "when the socket is disconnected, is a no-op" do
      socket = build_socket()
      refute socket.private[:phoenix_profiler]
      assert PhoenixProfiler.Utils.maybe_mount_profile(socket) == socket
    end

    test "puts a profile on the socket when the profiler is configured on the endpoint" do
      for endpoint <- [PhoenixProfilerTest.Endpoint, PhoenixProfilerTest.EndpointDisabled] do
        socket =
          endpoint
          |> build_socket()
          |> connect()
          |> PhoenixProfiler.Utils.maybe_mount_profile()

        assert %PhoenixProfiler.Profile{} = socket.private.phoenix_profiler
      end
    end

    test "when the profiler is not defined on the endpoint, is a no-op" do
      socket = PhoenixProfilerTest.EndpointNotConfigured |> build_socket() |> connect()
      assert PhoenixProfiler.Utils.maybe_mount_profile(socket) == socket
    end
  end
end
