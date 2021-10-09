defmodule PhoenixWeb.Profiler.Session do
  # Manages HTTP session state for the toolbar
  @moduledoc false
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.Server

  @session_key Profiler.session_key()
  @token_key Profiler.token_key()

  def listen(%Plug.Conn{} = conn, token) do
    {:ok, _} =
      DynamicSupervisor.start_child(
        Profiler.DynamicSupervisor,
        {Server, token: token}
      )

    conn
    |> Plug.Conn.put_session(@session_key, token)
    |> Plug.Conn.put_private(@session_key, token)
  end

  def topic(%{"phxweb_debug_session" => session_token}) do
    "#{@token_key}:#{session_token}"
  end

  def info(%{"phxweb_debug_session" => session, "pwdt" => token}) do
    Server.info(session, token)
  end

  @doc """
  Puts a new debug token on a given `conn`.
  """
  def apply_debug_token(%Plug.Conn{} = conn) do
    Plug.Conn.put_private(conn, @token_key, Profiler.random_unique_id())
  end

  @doc """
  Returns a maps of debug tokens from a given `conn`.
  """
  def tokens!(%Plug.Conn{} = conn) do
    {debug_token!(conn), session_token!(conn)}
  end

  @doc """
  Fetches the debug token for a given `conn`.

  Returns `{:ok, token}` or `:error` if no token is set.
  """
  @spec fetch_token(conn :: Plug.Conn.t()) :: {:ok, String.t()} | :error
  def fetch_token(%Plug.Conn{private: %{@token_key => token}}), do: {:ok, token}
  def fetch_token(%Plug.Conn{}), do: :error

  @doc """
  Returns the debug token for a given `conn`.

  Raises if no debug token is set.
  """
  def debug_token!(%Plug.Conn{} = conn) do
    case fetch_token(conn) do
      {:ok, token} -> token
      :error -> raise "debug token not set"
    end
  end

  def session_token!(%Plug.Conn{private: %{@session_key => token}}), do: token
  def session_token!(%Plug.Conn{}), do: "session token not set"

  @doc """
  Calls a profiler server with debug data from a given `conn`.
  """
  def profile_request(%Plug.Conn{private: %{@session_key => token}} = conn, extra \\ %{}) do
    request_info = Map.take(conn, [:host, :method, :path_info, :status])

    metadata =
      Map.take(conn.private, [
        :phoenix_action,
        :phoenix_controller,
        :phoenix_endpoint,
        :phoenix_router,
        :phoenix_view
      ])

    debug_info =
      extra
      |> Map.new()
      |> Map.merge(request_info)
      |> Map.merge(metadata)

    token
    |> Server.server_name()
    |> GenServer.call({Profiler, debug_info})
  end
end
