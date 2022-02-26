defmodule PhoenixProfiler.LiveViewTest do
  use ExUnit.Case
  alias Phoenix.LiveView.Socket

  defp build_socket(endpoint \\ PhoenixProfilerTest.Endpoint) do
    %Socket{endpoint: endpoint}
  end

  defp connect(%Socket{} = socket) do
    # TODO: replace with struct update when we require LiveView v0.15+.
    socket = Map.put(socket, :transport_pid, self())

    # TODO: remove when we require LiveView v0.15+.
    if Map.has_key?(socket, :connected?) do
      Map.put(socket, :connected?, true)
    else
      socket
    end
  end

  describe "on_mount/4" do
    test "when the socket is disconnected, is a no-op" do
      socket = build_socket()
      assert PhoenixProfiler.on_mount(:default, %{}, %{}, socket) == {:cont, socket}
    end

    test "when the profiler is enabled on the endpoint, configures an enabled profile" do
      {:ok, socket} = build_socket() |> connect() |> PhoenixProfiler.Configurator.configure()

      assert {:cont, %{private: %{phoenix_profiler: _profiler, phoenix_profiler_info: :enable}}} =
               PhoenixProfiler.on_mount(:default, %{}, %{}, socket)
    end

    test "when the profiler is disabled on the endpoint, configures a disabled profile" do
      socket =
        PhoenixProfilerTest.EndpointDisabled
        |> build_socket()
        |> connect()

      assert {:cont, %Socket{private: %{phoenix_profiler_info: :disable}}} =
               PhoenixProfiler.on_mount(:default, %{}, %{}, socket)
    end

    test "when the profiler is not defined on the endpoint, is a no-op" do
      socket = PhoenixProfilerTest.EndpointNotConfigured |> build_socket() |> connect()
      assert PhoenixProfiler.on_mount(:default, %{}, %{}, socket) == {:cont, socket}
    end
  end
end
