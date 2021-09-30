defmodule FriendsOfPhoenix.DebugTest do
  use ExUnit.Case
  doctest FriendsOfPhoenix.Debug

  test "greets the world" do
    assert FriendsOfPhoenix.Debug.hello() == :world
  end
end
