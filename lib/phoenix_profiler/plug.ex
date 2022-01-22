defmodule PhoenixProfiler.Plug do
  @moduledoc false
  import Plug.Conn
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ToolbarView
  require Logger

  @token_header_key "x-debug-token"
  @profiler_header_key "x-debug-token-link"

  def init(opts) do
    opts
  end

  # TODO: remove this clause when we add config for profiler except_patterns
  def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, _) do
    # this clause is to ignore the phoenix live reload iframe in case someone installs
    # the toolbar plug above the LiveReloader plug in their Endpoint.
    conn
  end

  def call(conn, _) do
    endpoint = conn.private.phoenix_endpoint
    config = endpoint.config(:phoenix_profiler)

    if config do
      conn
      |> PhoenixProfiler.Utils.enable_profiler(endpoint, config, System.system_time())
      |> before_send_profile(endpoint, config)
    else
      conn
    end
  end

  defp apply_profile_headers(conn, %Profile{} = profile) do
    conn
    |> put_resp_header(@token_header_key, profile.token)
    |> put_resp_header(@profiler_header_key, profile.url)
  end

  defp before_send_profile(conn, endpoint, config) do
    register_before_send(conn, fn conn ->
      case Map.get(conn.private, :phoenix_profiler) do
        %Profile{info: :enable} = profile ->
          conn
          |> apply_profile_headers(profile)
          |> PhoenixProfiler.Utils.on_send_resp(profile)
          |> maybe_inject_debug_toolbar(profile, endpoint, config)

        _ ->
          conn
      end
    end)
  end

  defp maybe_inject_debug_toolbar(%{resp_body: nil} = conn, _, _, _), do: conn

  defp maybe_inject_debug_toolbar(conn, profile, endpoint, config) do
    if html?(conn) do
      inject_debug_toolbar(conn, profile, endpoint, config)
    else
      conn
    end
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp inject_debug_toolbar(conn, profile, endpoint, config) do
    resp_body = IO.iodata_to_binary(conn.resp_body)

    if has_body?(resp_body) and Code.ensure_loaded?(endpoint) do
      [page | rest] = String.split(resp_body, "</body>")

      body = [page, debug_toolbar_assets_tag(conn, profile, config), "</body>" | rest]
      put_in(conn.resp_body, body)
    else
      conn
    end
  end

  defp html?(conn) do
    case get_resp_header(conn, "content-type") do
      [] -> false
      [type | _] -> String.starts_with?(type, "text/html")
    end
  end

  defp has_body?(resp_body), do: String.contains?(resp_body, "<body")

  defp debug_toolbar_assets_tag(conn, profile, config) do
    try do
      if Code.ensure_loaded?(PhoenixProfiler.ToolbarLive) do
        toolbar_attrs =
          case config[:toolbar_attrs] do
            attrs when is_list(attrs) -> attrs
            _ -> []
          end

        motion_class = if config[:reduce_motion], do: "no-motion"

        attrs =
          Keyword.merge(
            toolbar_attrs,
            id: "pwdt#{profile.token}",
            class: String.trim("phxprof-toolbar #{motion_class}"),
            role: "region",
            name: "Phoenix Web Debug Toolbar"
          )

        ToolbarView
        |> Phoenix.View.render("index.html", %{
          conn: conn,
          session: %{"_" => profile},
          profile: profile,
          toolbar_attrs: attrs(attrs)
        })
        |> Phoenix.HTML.Safe.to_iodata()
      else
        []
      end
    catch
      {kind, reason} ->
        IO.puts(Exception.format(kind, reason, __STACKTRACE__))
        []
    end
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
end
