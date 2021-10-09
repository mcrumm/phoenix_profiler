defmodule PhoenixWeb.Profiler.Session do
  # Manages HTTP session state for the toolbar
  @moduledoc false
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.{Request, Server}

  @private_key Request.session_key()
  @session_key Atom.to_string(@private_key)
  @token_key Atom.to_string(Request.token_key())

  def session_key, do: @session_key
  def token_key, do: @token_key

  def listen(%Plug.Conn{} = conn) do
    session_token = Profiler.random_unique_id()

    {:ok, _} =
      DynamicSupervisor.start_child(
        Profiler.DynamicSupervisor,
        {Server, token: session_token}
      )

    conn
    |> Plug.Conn.put_session(@session_key, session_token)
    |> Plug.Conn.put_private(@private_key, session_token)
  end

  def live_session(%Plug.Conn{} = conn) do
    %{
      @session_key => Request.session_token!(conn),
      @token_key => Request.debug_token!(conn)
    }
  end

  def topic(%{@session_key => session_token}) do
    "#{@session_key}:#{session_token}"
  end

  def topic_key(%{@token_key => debug_token}) do
    debug_token
  end

  def info(%{@session_key => session, @token_key => token}) do
    Server.info(session, token)
  end
end
