defmodule PhoenixWeb.ProfilerTest do
  use ExUnit.Case
  doctest PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.{Request, Session}

  test "keys" do
    assert Request.token_key() == :pwdt
    assert Request.session_key() == :phxweb_debug_session

    assert Session.token_key() == "pwdt"
    assert Session.session_key() == "phxweb_debug_session"
  end
end
