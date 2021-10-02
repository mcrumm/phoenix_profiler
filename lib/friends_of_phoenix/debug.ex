defmodule FriendsOfPhoenix.Debug do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias FriendsOfPhoenix.Debug
  require Logger

  @doc """
  Sends an entry to the debug server for the given `token`.
  """
  defdelegate put_entry(token, namespace, info), to: Debug.Server

  @doc """
  Returns a list of entries recorded for the given `token`.
  """
  defdelegate entries(token), to: Debug.Server

  @doc false
  def start_debug_server(token) do
    DynamicSupervisor.start_child(
      Debug.DynamicSupervisor,
      {Debug.Server, [token: token]}
    )
  end

  @behaviour Plug
  @token_key :fophx_debug
  @live_socket_path_default "/live"

  @doc """
  Returns the key used when storing the debug token.
  """
  def token_key, do: @token_key

  phoenix_path = Application.app_dir(:phoenix, "priv/static/phoenix.js")
  live_view_path = Application.app_dir(:phoenix_live_view, "priv/static/phoenix_live_view.js")

  @external_resource phoenix_path
  @external_resource live_view_path

  @phoenix_js File.read!(phoenix_path)
  @live_view_js File.read!(live_view_path)

  @impl Plug
  def init(opts) do
    session =
      case opts[:session] do
        {m, f, args} = mfa when is_atom(m) and is_atom(f) and is_list(args) -> mfa
        opts -> Plug.Session.init(opts)
      end

    iframe_attrs =
      case opts[:iframe_attrs] do
        attrs when is_list(attrs) -> attrs
        _ -> []
      end

    %{
      session: session,
      iframe_attrs: iframe_attrs,
      live_socket_path: opts[:live_socket_path] || @live_socket_path_default
    }
  end

  defp session_options({m, f, args}), do: apply(m, f, args)
  defp session_options(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["fophx", "debug.js" | _]} = conn, config) do
    %{live_socket_path: url} = config

    conn
    |> Plug.Session.call(session_options(config.session))
    |> Plug.Conn.fetch_session()
    |> Phoenix.Controller.protect_from_forgery()
    |> put_resp_content_type("text/html")
    |> send_resp(200, [
      @phoenix_js,
      @live_view_js,
      ?\n,
      ~s<var csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");\n>,
      ~s<var liveSocket = new LiveView.LiveSocket("#{url}", Phoenix.Socket, { params: { _csrf_token: csrfToken } });\n>,
      ~s<liveSocket.connect();\n>
    ])
    |> halt()
  end

  @impl Plug
  def call(%Plug.Conn{path_info: ["fophx", "debug", "frame" | _suffix]} = conn, opts) do
    conn = Plug.Conn.fetch_query_params(conn)
    token = conn.params["token"] || raise "token not found in iframe request"
    session = %{to_string(@token_key) => token}

    conn
    |> Plug.Session.call(session_options(opts.session))
    |> Plug.Conn.fetch_session()
    |> Phoenix.Controller.protect_from_forgery()
    |> Plug.Conn.assign(@token_key, token)
    |> Phoenix.Controller.put_root_layout({Debug.View, "root.html"})
    |> Phoenix.Controller.put_layout({Debug.View, "app.html"})
    |> Phoenix.LiveView.Controller.live_render(Debug.ToolbarLive, session: session)
    |> halt()
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
    :telemetry.execute([:fophx, :debug, :start], %{system_time: System.system_time()}, %{})

    conn
    |> put_private(@token_key, generate_token())
    |> before_send_inject_debug_bar(conn.private.phoenix_endpoint, start_time, config)
  end

  defp before_send_inject_debug_bar(conn, endpoint, start_time, config) do
    register_before_send(conn, fn conn ->
      if conn.resp_body != nil and html?(conn) do
        resp_body = IO.iodata_to_binary(conn.resp_body)

        if has_body?(resp_body) and :code.is_loaded(endpoint) do
          token = conn.private.fophx_debug
          {:ok, pid} = start_debug_server(token)
          Logger.debug("Started debug server at #{inspect(pid)} for token #{token}")
          [page | rest] = String.split(resp_body, "</body>")
          body = [page, debug_assets_tag(conn, endpoint, token, config), "</body>" | rest]
          conn = put_in(conn.resp_body, body)

          duration = System.monotonic_time() - start_time
          :telemetry.execute([:fophx, :debug, :stop], %{duration: duration}, %{conn: conn})

          conn
        else
          conn
        end
      else
        conn
      end
    end)
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp html?(conn) do
    case get_resp_header(conn, "content-type") do
      [] -> false
      [type | _] -> String.starts_with?(type, "text/html")
    end
  end

  defp has_body?(resp_body), do: String.contains?(resp_body, "<body")

  defp debug_assets_tag(conn, _endpoint, token, config) do
    path = conn.private.phoenix_endpoint.path("/fophx/debug/frame?token=#{token}")

    attrs =
      Keyword.merge(
        [
          src: path,
          style: "border:0px none;width:100%;"
        ],
        config.iframe_attrs
      )

    IO.iodata_to_binary([
      ~s[<div style="left: 0px; border: 0px none; height: 44px; position: fixed; width: 100%; bottom: 0px;">],
      "<iframe",
      attrs(attrs),
      "></iframe>",
      "</div>"
    ])
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
