defmodule PhoenixWeb.Profiler.Request do
  # Operations over Plug.Conn
  @moduledoc false
  import Plug.Conn
  alias PhoenixWeb.Profiler
  alias PhoenixWeb.Profiler.Dumped
  alias PhoenixWeb.Profiler.Routes

  @token_key :pwdt
  @token_header_key "x-debug-token"

  @doc """
  Returns an atom that is the debug token key.
  """
  def token_key, do: @token_key

  @doc """
  Returns a string that is the debug token header key.
  """
  def token_header_key, do: @token_header_key

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

    metrics = %{
      endpoint_duration: Process.get(:phxweb_endpoint_duration),
      memory: memory
    }

    route = Routes.route_info(conn)

    profile = %{
      conn: Map.delete(conn, :resp_body),
      dumped: Dumped.flush(),
      metrics: metrics,
      route: route
    }

    {token, profile}
  end

  @doc """
  Returns the debug token stored on a given `conn`.

  Raises if no debug token was set.
  """
  def debug_token!(%Plug.Conn{private: %{@token_key => token}}), do: token
  def debug_token!(%Plug.Conn{}), do: raise("debug token not set")
end
