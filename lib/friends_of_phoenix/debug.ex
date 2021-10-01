defmodule FriendsOfPhoenix.Debug do
  @moduledoc """
  Debug Toolbar for Phoenix HTML requests.

  ## Goals

  * Reponse data (status code, headers?, session [y|n], etc.)
  * Route/Path - controller/action/view, live_view/live_action, etc.
  * Basic diagnostics - response time, heap size?
  * Mailer preview
  * Debug assigns
  * Debug LiveView crashes

  ### Non-Goals

  * Replace LiveDashboard
  * Run in production

  ## Getting Started

  To use the debug toolbar, your app must meet the following requirements:

    * You must have [`LiveView`](`Phoenix.LiveView`) installed and configured.

  To install the debug toolbar, you need the following steps:

    * Add `{:fophx_debug, "~> 0.1.0", runtime: Mix.env() == :dev}` to your mix.exs.

    * Add `plug #{inspect(__MODULE__)}` at the bottom of the `if code_reloading? do` block in your Endpoint.

    * For LiveView debugging, add ` if Mix.env() == :dev, do: on_mount({#{inspect(__MODULE__.Live)}, __MODULE__})` to
      the body of the `:live_view` function in your `_web.ex` file.

  """
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
  def start_debug_server do
    token = generate_token()

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Debug.DynamicSupervisor,
        {Debug.Server, [token: token]}
      )

    Logger.debug("Started debug server at #{inspect(pid)} for token #{token}")

    {:ok, token}
  end

  @behaviour Plug
  @config_key :fophx_debug
  @token_key :fophx_debug

  @doc """
  Returns the key used when storing the debug token.
  """
  def token_key, do: @token_key

  @impl Plug
  def init(opts), do: opts

  # TODO: Inject JS to get LiveView connected (phoenix, phoenix_html, phoenix_live_view, app)
  @impl Plug
  def call(%Plug.Conn{path_info: ["fophx", "debug", "frame" | _suffix]} = conn, _) do
    conn = Plug.Conn.fetch_query_params(conn)
    token = conn.params["token"] || raise "token not found in iframe request"
    session = %{to_string(@token_key) => token}

    conn
    |> Plug.Conn.assign(@token_key, token)
    |> Phoenix.Controller.put_root_layout({Debug.View, "root.html"})
    |> Phoenix.Controller.put_layout({Debug.View, "app.html"})
    |> Phoenix.LiveView.Controller.live_render(Debug.ToolbarLive, session: session)
    |> halt()
  end

  @impl Plug
  def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, _) do
    conn
  end

  @impl Plug
  def call(conn, _) do
    start_time = System.monotonic_time()
    :telemetry.execute([:fophx, :debug, :start], %{system_time: System.system_time()}, %{})
    endpoint = conn.private.phoenix_endpoint
    config = endpoint.config(@config_key) || []

    before_send_inject_debug_bar(conn, endpoint, start_time, config)
  end

  defp before_send_inject_debug_bar(conn, endpoint, start_time, config) do
    register_before_send(conn, fn conn ->
      if conn.resp_body != nil and html?(conn) do
        resp_body = IO.iodata_to_binary(conn.resp_body)

        if has_body?(resp_body) and :code.is_loaded(endpoint) do
          {:ok, token} = start_debug_server()
          [page | rest] = String.split(resp_body, "</body>")
          body = [page, debug_assets_tag(conn, endpoint, token, config), "</body>" | rest]
          conn = put_in(conn.resp_body, body)

          conn =
            conn
            |> Plug.Conn.put_private(@token_key, token)
            |> Plug.Conn.put_session(@token_key, token)

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

  defp debug_assets_tag(conn, endpoint, token, config) do
    path =
      conn.private.phoenix_endpoint.path("/fophx/debug/frame#{suffix(endpoint)}?token=#{token}")

    attrs =
      Keyword.merge(
        [
          src: path,
          style: "border:0px none;width:100%;"
        ],
        Keyword.get(config, :iframe_attrs, [])
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

  defp suffix(endpoint), do: endpoint.config(@config_key)[:suffix] || ""
end
