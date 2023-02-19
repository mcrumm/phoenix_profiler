defmodule PhoenixProfiler.ServerTest do
  use ExUnit.Case
  alias PhoenixProfiler.Server
  doctest Server

  describe "subscribe/1" do
    test "returns :error when no owner is registered" do
      assert Server.subscribe(self()) == :error
    end

    test "returns {:ok, token} for a registered owner" do
      {:ok, token} = PhoenixProfiler.Server.put_owner_token(:endpoint)
      assert {:ok, ^token} = Server.subscribe(self())
    end

    test "sends telemetry for owner" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token(:endpoint)
      {:ok, token} = Server.subscribe(self())

      time = System.unique_integer()
      :ok = test_telemetry(time)

      assert_receive_telemetry(token, time)
    end

    test "receives telemetry for $callers" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token(:endpoint)
      {:ok, token} = Server.subscribe(self())

      inner_1 = System.unique_integer()
      inner_2 = System.unique_integer()

      Task.async(fn ->
        :ok = test_telemetry(inner_1)
        Task.async(fn -> test_telemetry(inner_2) end) |> Task.await()
      end)
      |> Task.await()

      assert_receive_telemetry(token, inner_1)
      assert_receive_telemetry(token, inner_2)
    end

    test "monitors owner pid and cleans up tables on :DOWN", %{test: test} do
      test_pid = self()

      task =
        Task.async(fn ->
          {:ok, token} = Server.put_owner_token(test)
          send(test_pid, {:token, token, self()})

          receive do
            :done -> :ok
          end
        end)

      assert_receive {:token, token, task_pid}
      ref = Process.monitor(task_pid)

      assert [{^task_pid, ^token}] = :ets.lookup(Server.Live, task_pid)

      {:ok, ^token} = Server.subscribe(task_pid)
      assert [{^token, ^test_pid}] = :ets.lookup(Server.Listener, token)

      send(task_pid, :done)

      :ok = Task.await(task)
      assert_receive {:DOWN, ^ref, _, ^task_pid, _}

      # force sync by registering/subscribing in another process
      {:ok, _} = Server.put_owner_token(test)
      {:ok, _} = Server.subscribe(self())

      assert :ets.lookup(Server.Live, task_pid) == []
      assert :ets.lookup(Server.Listener, token) == []
    end

    test "disable and enable telemetry messages" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token(:endpoint)
      {:ok, token} = Server.subscribe(self())

      :ok = test_telemetry(msg_1 = System.unique_integer())
      assert_receive_telemetry(token, msg_1)

      Server.profiling(false)
      :ok = test_telemetry(msg_2 = System.unique_integer())

      Server.profiling(true)
      :ok = test_telemetry(msg_3 = System.unique_integer())

      # Ensure we receive the 3rd message...
      assert_receive_telemetry(token, msg_3)

      # ...then we can ensure we never received the 2nd message.
      refute_received_telemetry(token, msg_2)
    end

    test "disable and enable are idempotent" do
      {:ok, _} = PhoenixProfiler.Server.put_owner_token(:endpoint)
      {:ok, token} = Server.subscribe(self())

      :ok = test_telemetry(msg_1 = System.unique_integer())

      _ = Server.profiling(false)
      _ = Server.profiling(false)

      :ok = test_telemetry(msg_2 = System.unique_integer())

      _ = Server.profiling(true)
      _ = Server.profiling(true)

      :ok = test_telemetry(msg_3 = System.unique_integer())

      assert_receive_telemetry(token, msg_1)
      assert_receive_telemetry(token, msg_3)

      refute_received_telemetry(token, msg_2)
    end
  end

  @test_telemetry_event [:phoenix_profiler, :internal, :this_is_only_used_for_testing]

  defp test_telemetry(time) do
    :telemetry.execute(@test_telemetry_event, %{system_time: time}, %{})
  end

  defp assert_receive_telemetry(token, time) do
    assert_receive {PhoenixProfiler.Server, ^token,
                    {:telemetry, @test_telemetry_event, ^time, nil}}
  end

  defp refute_received_telemetry(token, time) do
    refute_received {PhoenixProfiler.Server, ^token,
                     {:telemetry, @test_telemetry_event, ^time, nil}}
  end
end
