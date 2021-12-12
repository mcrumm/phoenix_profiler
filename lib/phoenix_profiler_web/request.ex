defmodule PhoenixProfilerWeb.Request do
  # Operations over Plug.Conn
  @moduledoc false
  import Plug.Conn
  alias PhoenixProfiler.Utils
  alias PhoenixProfilerWeb.Routes

  @token_key :pwdt
  @token_header_key "x-debug-token"
  @profiler_header_key "x-debug-profiler"

  @doc """
  Returns an atom that is the debug token key.
  """
  def token_key, do: @token_key

  @doc """
  Returns a string that is the debug token header key.
  """
  def token_header_key, do: @token_header_key

  @doc """
  Returns a string that is the debug profiler header key.
  """
  def profiler_header_key, do: @profiler_header_key

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
    token = Utils.random_unique_id()

    conn
    |> put_private(@token_key, token)
    |> put_resp_header(@token_header_key, token)
  end

  @doc """
  Puts a profiler header on the response, if configured.
  """
  def apply_profiler(%Plug.Conn{} = conn, opts) do
    maybe_put_profiler_header(conn, opts)
  end

  defp maybe_put_profiler_header(conn, opts) do
    if profiler_url = profiler_url(conn, opts) do
      put_resp_header(conn, @profiler_header_key, profiler_url)
    else
      conn
    end
  end

  defp profiler_url(conn, true) do
    conn.private.phoenix_endpoint.url() <>
      "/dashboard/_profiler?nav=requests&token=" <> debug_token!(conn)
  end

  defp profiler_url(_conn, _opts), do: nil

  @doc """
  Profiles a given `conn`.
  """
  def profile_request(%Plug.Conn{private: %{@token_key => token}} = conn) do
    # Measurements
    {:memory, bytes} = Process.info(self(), :memory)
    memory = div(bytes, 1_024)

    metrics = %{
      endpoint_duration: Process.get(:phxprof_endpoint_duration),
      memory: memory
    }

    at = Process.get(:phxprof_profiler_time)
    assigns = Map.delete(conn.assigns, :content)

    profile = %{
      at: at,
      conn: %{conn | resp_body: nil, assigns: assigns},
      metrics: metrics
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
