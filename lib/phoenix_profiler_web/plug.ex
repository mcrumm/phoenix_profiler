defmodule PhoenixProfilerWeb.Plug do
  @moduledoc false
  import Plug.Conn
  alias PhoenixProfilerWeb.{Request, ToolbarView}
  require Logger

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
      start_time = System.monotonic_time()

      conn
      |> Request.apply_profiler(config)
      |> telemetry(:start, %{system_time: System.system_time()})
      |> before_send_profile(start_time, endpoint, config)
    else
      conn
    end
  end

  defp before_send_profile(conn, start_time, endpoint, config) do
    register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time

      conn
      |> telemetry(:stop, %{duration: duration})
      |> maybe_inject_debug_toolbar(endpoint, config)
    end)
  end

  defp telemetry(conn, action, measurements) when action in [:start, :stop] do
    :telemetry.execute([:phxprof, :plug, action], measurements, %{conn: conn})
    conn
  end

  defp maybe_inject_debug_toolbar(%{resp_body: nil} = conn, _, _), do: conn

  defp maybe_inject_debug_toolbar(conn, endpoint, config) do
    if html?(conn) do
      inject_debug_toolbar(conn, endpoint, config)
    else
      conn
    end
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp inject_debug_toolbar(conn, endpoint, config) do
    resp_body = IO.iodata_to_binary(conn.resp_body)

    if has_body?(resp_body) and Code.ensure_loaded?(endpoint) do
      [page | rest] = String.split(resp_body, "</body>")

      body = [page, debug_toolbar_assets_tag(conn, endpoint, config), "</body>" | rest]
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

  defp debug_toolbar_assets_tag(conn, _endpoint, config) do
    try do
      if Code.ensure_loaded?(PhoenixProfilerWeb.ToolbarLive) do
        token = Request.debug_token!(conn)
        motion_class = if System.get_env("PHOENIX_PROFILER_REDUCED_MOTION"), do: "no-motion"

        toolbar_attrs =
          case config[:toolbar_attrs] do
            attrs when is_list(attrs) -> attrs
            _ -> []
          end

        attrs =
          Keyword.merge(
            toolbar_attrs,
            id: Request.toolbar_id(conn),
            class: String.trim("phxprof-toolbar #{motion_class}"),
            role: "region",
            name: "Phoenix Web Debug Toolbar"
          )

        ToolbarView
        |> Phoenix.View.render("index.html", %{
          conn: conn,
          session: %{"token" => token, "profiler" => config[:profiler], "node" => node()},
          token: token,
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
