defmodule PhoenixWeb.ProfilerTest do
  use ExUnit.Case
  doctest PhoenixWeb.Profiler

  test "token_key/0" do
    assert PhoenixWeb.Profiler.token_key() == :pwdt
  end
end
