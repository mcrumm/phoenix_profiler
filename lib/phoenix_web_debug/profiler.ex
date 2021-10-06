defmodule PhoenixWeb.Profiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias PhoenixWeb.Profiler
  require Logger

  @doc false
  def track(%Phoenix.LiveView.Socket{} = socket, token, meta)
      when is_binary(token) and token != "" and is_map(meta) do
    if Phoenix.LiveView.connected?(socket) do
      {:ok, ref} =
        Profiler.Presence.track(
          self(),
          Profiler.Server.topic(token),
          inspect(self()),
          meta |> Map.put(:node, Node.self()) |> Map.put(:pid, self())
        )

      Phoenix.LiveView.assign(socket, :ref, ref)
    else
      socket
    end
  end

  @behaviour Plug
  @token_key :pwdt
  @live_socket_path_default "/live"

  @doc """
  Readies a given `conn` for profiling.

  Raises if a debug token is already set on the conn.
  """
  def profile(%Plug.Conn{} = conn) do
    put_debug_token(conn, generate_token())
  end

  @doc """
  Puts a debug token on a given `conn`.

  Raises if a token is already set.
  """
  def put_debug_token(%Plug.Conn{private: %{@token_key => token}}, _) do
    raise ArgumentError, "Expected a conn without a debug token, got: #{inspect(token)}"
  end

  def put_debug_token(%Plug.Conn{} = conn, token) when is_binary(token) and token != "" do
    put_private(conn, @token_key, token)
  end

  @doc """
  Starts a profiler server for a given `conn`.

  The `conn` must have already been provided a debug token,
  for instance by invoking `profile/1`.
  """
  def start(conn, extra \\ %{})

  def start(%Plug.Conn{private: %{@token_key => token}} = conn, extra) do
    request_info = Map.take(conn, [:host, :method, :path_info, :status])

    metadata =
      Map.take(conn.private, [
        :phoenix_action,
        :phoenix_controller,
        :phoenix_endpoint,
        :phoenix_router,
        :phoenix_view
      ])

    profiler_info =
      extra
      |> Map.new()
      |> Map.merge(request_info)
      |> Map.merge(metadata)

    with {:ok, pid} <-
           DynamicSupervisor.start_child(
             Profiler.DynamicSupervisor,
             {Profiler.Server, token: token, profiler_info: profiler_info}
           ) do
      {:ok, pid, token}
    end
  end

  def start(%Plug.Conn{} = _conn, _extra) do
    raise "debug token required for Profiler.start/2"
  end

  @doc """
  Returns the key used when storing the profiler token.
  """
  def token_key, do: @token_key

  @impl Plug
  def init(opts) do
    toolbar_attrs =
      case opts[:toolbar_attrs] do
        attrs when is_list(attrs) -> attrs
        _ -> []
      end

    %{
      toolbar_attrs: toolbar_attrs,
      live_socket_path: opts[:live_socket_path] || @live_socket_path_default
    }
  end

  @impl Plug
  def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, _) do
    # this clause is to ignore the phoenix live reload iframe in case someone installs
    # the toolbar plug above the LiveReloader plug in their Endpoint.
    conn
  end

  @impl Plug
  def call(conn, config) do
    start_time = System.monotonic_time()

    conn
    |> profile()
    |> before_send_inject_debug_toolbar(conn.private.phoenix_endpoint, start_time, config)
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp before_send_inject_debug_toolbar(conn, endpoint, start_time, config) do
    register_before_send(conn, fn conn ->
      if conn.resp_body != nil and html?(conn) do
        resp_body = IO.iodata_to_binary(conn.resp_body)

        if has_body?(resp_body) and :code.is_loaded(endpoint) do
          [page | rest] = String.split(resp_body, "</body>")
          duration = System.monotonic_time() - start_time

          with {:ok, pid, token} <- start(conn, %{duration: duration}) do
            Logger.debug("Started profiler server at #{inspect(pid)} for token #{token}")

            body = [page, profiler_assets_tag(conn, endpoint, token, config), "</body>" | rest]
            conn = put_in(conn.resp_body, body)

            conn
          else
            _ ->
              conn
          end
        else
          conn
        end
      else
        conn
      end
    end)
  end

  defp html?(conn) do
    case get_resp_header(conn, "content-type") do
      [] -> false
      [type | _] -> String.starts_with?(type, "text/html")
    end
  end

  defp has_body?(resp_body), do: String.contains?(resp_body, "<body")

  defp profiler_assets_tag(conn, _endpoint, token, config) do
    attrs =
      Keyword.merge(
        config.toolbar_attrs,
        id: "pwdt#{token}",
        class: "phxweb-toolbar",
        role: "region",
        name: "Phoenix Web Debug Toolbar"
      )

    Profiler.View
    |> Phoenix.View.render("toolbar.html", %{
      conn: conn,
      session: %{to_string(@token_key) => token},
      token: token,
      toolbar_attrs: attrs(attrs)
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp attrs(attrs) do
    Enum.map(attrs, fn
      {_key, nil} -> []
      {_key, false} -> []
      {key, true} -> [?\s, key(key)]
      {key, value} -> [?\s, key(key), ?=, ?", value(value), ?"]
    end)
  end

  defp key(key) do
    key
    |> to_string()
    |> String.replace("_", "-")
    |> Plug.HTML.html_escape_to_iodata()
  end

  defp value(value) do
    value
    |> to_string()
    |> Plug.HTML.html_escape_to_iodata()
  end

  # Request ID generation
  # Copyright (c) 2013 Plataformatec.
  # https://github.com/elixir-plug/plug/blob/fb6b952cf93336dc79ec8d033e09a424d522ce56/lib/plug/request_id.ex
  # Note the segment sizes have been adjusted to generated shorter strings,
  # and the adjusted parameters have not been tested exhaustively.
  defp generate_token do
    binary = <<
      System.system_time(:nanosecond)::16,
      :erlang.phash2({node(), self()}, 16_777_216)::8,
      :erlang.unique_integer()::8
    >>

    Base.url_encode64(binary, padding: false)
  end
end
