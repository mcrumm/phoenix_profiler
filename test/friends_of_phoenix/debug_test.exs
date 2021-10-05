defmodule PhoenixWeb.DebugTest do
  use ExUnit.Case
  doctest PhoenixWeb.Debug

  test "token_key/0" do
    assert PhoenixWeb.Debug.token_key() == :pwdt
  end
end
