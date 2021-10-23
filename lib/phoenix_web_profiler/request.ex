defmodule PhoenixWeb.Profiler.Request do
  # Operations over Plug.Conn
  @moduledoc false
  import Plug.Conn
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.Dumped

  @session_key :phxweb_debug_session
  @token_key :pwdt
  @token_header_key "x-debug-token"

  @doc """
  Returns an atom that is the debug session key.
  """
  def session_key, do: @session_key

  @doc """
  Returns an atom that is the debug token key.
  """
  def token_key, do: @token_key

  @doc """
  Returns the id of the toolbar element.
  """
  def toolbar_id(%Plug.Conn{private: %{@token_key => debug_token}}) do
    "#{@token_key}#{debug_token}"
  end

  @doc """
  Puts a new debug token on a given `conn`.
  """
  def apply_debug_token(%Plug.Conn{} = conn) do
    token = Profiler.random_unique_id()

    conn
    |> put_private(@token_key, token)
    |> put_resp_header(@token_header_key, token)
  end

  @doc """
  Profiles a given `conn`.
  """
  def profile_request(%Plug.Conn{private: %{@token_key => token}} = conn) do
    # Measurements
    {:memory, bytes} = Process.info(self(), :memory)
    memory = div(bytes, 1_024)

    {token,
     conn
     |> request_info()
     |> Map.merge(%{
       dumped: Dumped.flush(),
       memory: memory
     })}
  end

  def debug_token!(%Plug.Conn{private: %{@token_key => token}}), do: token
  def debug_token!(%Plug.Conn{}), do: raise("debug token not set")

  def session_token!(%Plug.Conn{private: %{@session_key => token}}), do: token

  def session_token!(%Plug.Conn{private: private}),
    do: raise("session token not found in #{inspect(private)}")

  @doc """
  Returns request metadata for a given `conn`.
  """
  def request_info(%Plug.Conn{} = conn) do
    request = Map.take(conn, [:host, :method, :path_info, :status])

    metadata =
      Map.take(conn.private, [
        :phoenix_action,
        :phoenix_controller,
        :phoenix_endpoint,
        :phoenix_router,
        :phoenix_view,
        @session_key,
        @token_key
      ])

    Map.merge(request, metadata)
  end
end
