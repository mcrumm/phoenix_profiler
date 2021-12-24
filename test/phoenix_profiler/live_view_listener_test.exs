defmodule PhoenixProfiler.LiveViewListenerTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint PhoenixProfilerTest.Endpoint

  alias PhoenixProfiler.LiveViewListener

  defmodule PageLive do
    use Phoenix.LiveView

    def mount(params, session, socket) do
      {:cont, socket} = PhoenixProfiler.on_mount(:default, params, session, socket)
      {:ok, socket}
    end

    def render(assigns) do
      ~L"""
      <div>
        <button id="boom" phx-click="boom">boom</button>
      </div>
      """
    end

    def handle_event("boom", _, _socket) do
      raise "boom"
    end

    def handle_call({:run, func}, _, socket) do
      func.(socket)
    end
  end

  describe "listen/2" do
    test "raises when the socket is not connected" do
      assert_raise ArgumentError,
                   "listen/2 may only be called when the socket is connected.",
                   fn ->
                     LiveViewListener.listen(%Phoenix.LiveView.Socket{})
                   end
    end

    test "subscribes the caller to LiveView exceptions" do
      {:ok, view, _html} = live_profile_isolated(build_conn(), PageLive)

      assert exits_with(view, RuntimeError, fn ->
               view |> element("button", "boom") |> render_click()
             end) =~ "boom"

      assert_received {:exception, :error, %RuntimeError{message: "boom"}, [_ | _]}
    end

    test "unsubscribes when the profiler is disabled on the socket" do
      {:ok, view, _html} = live_profile_isolated(build_conn(), PageLive)

      disable_profiler(view)

      assert exits_with(view, RuntimeError, fn ->
               view |> element("button", "boom") |> render_click()
             end) =~ "boom"

      refute_received {:exception, :error, _, _}
    end
  end

  defp live_profile_isolated(%Plug.Conn{} = conn, mod) when is_atom(mod) do
    with {:ok, view, html} <- live_isolated(conn, mod),
         {:ok, socket} <- run(view, &{:reply, {:ok, &1}, &1}),
         {:ok, _} <- LiveViewListener.listen(socket) do
      {:ok, view, html}
    end
  end

  defp disable_profiler(lv) do
    run(lv, fn socket ->
      {:reply, :ok, PhoenixProfiler.disable(socket)}
    end)
  end

  defp run(lv, func, timeout \\ 100) when is_function(func, 1) do
    GenServer.call(lv.pid, {:run, func}, timeout)
  end

  defp exits_with(lv, kind, func) do
    Process.unlink(proxy_pid(lv))

    try do
      func.()
      raise "expected to exit with #{inspect(kind)}"
    catch
      :exit, {{%mod{message: msg}, _}, _} when mod == kind -> msg
    end
  end

  defp proxy_pid(%{proxy: {_ref, _topic, pid}}), do: pid
end
