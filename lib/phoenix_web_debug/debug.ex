defmodule PhoenixWeb.Debug do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias PhoenixWeb.Debug
  require Logger

  @doc false
  def track(%Phoenix.LiveView.Socket{} = socket, token, meta)
      when is_binary(token) and token != "" and is_map(meta) do
    if Phoenix.LiveView.connected?(socket) do
      {:ok, ref} =
        Debug.Presence.track(
          self(),
          Debug.Server.topic(token),
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

  @doc false
  def start_debug_server(conn, extra \\ %{})

  def start_debug_server(%Plug.Conn{private: %{@token_key => token}} = conn, extra) do
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

    with {:ok, pid} <-
           DynamicSupervisor.start_child(
             Debug.DynamicSupervisor,
             {Debug.Server, token: token, debug_info: debug_info}
           ) do
      {:ok, pid, token}
    end
  end

  def start_debug_server(%Plug.Conn{} = _conn, _extra) do
    raise "start_debug_server requires a token to be set on the conn"
  end

  @doc """
  Returns the key used when storing the debug token.
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
    |> put_private(@token_key, generate_token())
    |> before_send_inject_debug_bar(conn.private.phoenix_endpoint, start_time, config)
  end

  defp before_send_inject_debug_bar(conn, endpoint, start_time, config) do
    register_before_send(conn, fn conn ->
      if conn.resp_body != nil and html?(conn) do
        resp_body = IO.iodata_to_binary(conn.resp_body)

        if has_body?(resp_body) and :code.is_loaded(endpoint) do
          [page | rest] = String.split(resp_body, "</body>")
          duration = System.monotonic_time() - start_time

          with {:ok, pid, token} <- start_debug_server(conn, %{duration: duration}) do
            Logger.debug("Started debug server at #{inspect(pid)} for token #{token}")

            body = [page, debug_assets_tag(conn, endpoint, token, config), "</body>" | rest]
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
    attrs =
      Keyword.merge(
        config.toolbar_attrs,
        id: "pwdt#{token}",
        class: "phxweb-toolbar",
        role: "region",
        name: "Phoenix Web Debug Toolbar"
      )

    Debug.View
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
