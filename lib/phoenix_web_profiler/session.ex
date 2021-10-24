defmodule PhoenixWeb.Profiler.Session do
  # Manages HTTP session state for the toolbar
  @moduledoc false
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.{PubSub, Request, Requests, Server}

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

  @doc """
  Subscribes a LiveView process to the profiler session.
  """
  def subscribe(%Phoenix.LiveView.Socket{private: %{topic: nil}} = socket) do
    # No-op when the socket when the topic was not provided or invalid
    socket
  end

  def subscribe(%Phoenix.LiveView.Socket{private: %{topic: topic}} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(PubSub, topic)
    end

    socket
  end

  @doc """
  Builds the debug session data.

  Returns `{debug_token :: String.t(), session :: map()}`.
  """
  def debug_session(%Plug.Conn{} = conn) do
    debug_token = Request.debug_token!(conn)

    session = %{
      @token_key => debug_token
    }

    session =
      case Map.fetch(conn.private, @private_key) do
        {:ok, session_token} -> Map.put(session, @session_key, session_token)
        :error -> session
      end

    {debug_token, session}
  end

  def session_token!(%Plug.Conn{private: %{@private_key => session_token}}) do
    session_token
  end

  def session_token!(%Plug.Conn{}), do: raise("session token not set")

  def topic(%{@session_key => session_token}) do
    "#{@session_key}:#{session_token}"
  end

  def topic(%{}) do
    nil
  end

  def topic_key(%{@token_key => debug_token}) do
    debug_token
  end

  def info(%{@token_key => token}) do
    token |> Requests.multi_get() |> List.first()
  end
end
