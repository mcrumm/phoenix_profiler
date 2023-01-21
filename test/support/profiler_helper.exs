defmodule ProfilerHelper do
  @moduledoc """
  Helpers for testing profilers.

  Must not be used to test endpoints because they perform
  some setup that could skew the results of the endpoint
  tests.
  """

  import Plug.Conn, only: [put_private: 3]
  alias PhoenixProfiler.Profiler

  defmacro __using__(_) do
    quote do
      use Plug.Test
      import ProfilerHelper
    end
  end

  def profile_thru(%Plug.Conn{} = conn, endpoint) do
    {:ok, profile} = Profiler.preflight(endpoint)
    {:ok, pid} = Profiler.start_collector(conn, profile)

    conn
    |> put_private(:phoenix_endpoint, endpoint)
    |> put_private(:phoenix_profiler, profile)
    |> put_private(:phoenix_profiler_collector, pid)
  end
end
