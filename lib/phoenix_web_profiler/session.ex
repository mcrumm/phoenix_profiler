defmodule PhoenixWeb.Profiler.Session do
  # Manages HTTP session state for the toolbar
  @moduledoc false
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.{Presence, PubSub, Request, Requests, Server}

  @private_key Request.session_key()
  @session_key Atom.to_string(@private_key)
  @token_key Atom.to_string(Request.token_key())

  def session_key, do: @session_key
  def token_key, do: @token_key

  def listen(%Plug.Conn{} = conn) do
    debug_token = Request.debug_token!(conn)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Profiler.DynamicSupervisor,
        {Server, token: debug_token}
      )

    continue(conn, pid)
  end

  @doc """
  Configures private/session data for a given `conn`.
  """
  def continue(conn, pid) do
    conn
    |> Plug.Conn.put_private(@private_key, pid)
    |> Plug.Conn.put_session(@token_key, Request.debug_token!(conn))
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
  Tracks the caller as part of the profiler session.
  """
  def track(%Phoenix.LiveView.Socket{} = socket, session, meta)
      when is_map(session) and is_map(meta) do
    if Phoenix.LiveView.connected?(socket) do
      topic = topic(session)
      key = topic_key(session)

      if topic do
        {:ok, ref} =
          Presence.track(
            self(),
            topic,
            key,
            meta
            |> Map.put(:node, node())
            |> Map.put(:pid, self())
          )

        Phoenix.LiveView.assign(socket, :ref, ref)
      else
        require Logger

        Logger.debug("""
        The Phoenix Web Debug Toolbar could not connect because no session debug token was found.

        Did you remember to add PhoenixWeb.LiveProfiler to the
        :browser pipeline in your router? For example:

        pipeline :browser do
          # plugs...
          plug PhoenixWeb.LiveProfiler
        end
        """)

        socket
      end
    else
      socket
    end
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
