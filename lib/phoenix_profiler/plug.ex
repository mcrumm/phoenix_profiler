defmodule PhoenixProfiler.Plug do
  @moduledoc false
  import Plug.Conn
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ToolbarView
  require Logger

  @behaviour Plug

  @token_header_key "x-debug-token"
  @profiler_header_key "x-debug-token-link"

  @impl Plug
  def init(opts) do
    opts
  end

  @impl Plug
  def call(conn, _) do
    endpoint = conn.private.phoenix_endpoint
    start_time = System.monotonic_time()

    case conn.private do
      %{phoenix_profiler: %Profile{}} ->
        conn
        |> telemetry_execute(:start, %{system_time: System.system_time()})
        |> before_send_profile(endpoint, [], start_time)

      _ ->
        conn
    end
  end

  defp apply_profile_headers(conn, %Profile{} = profile) do
    conn
    |> put_resp_header(@token_header_key, profile.token)
    |> put_resp_header(@profiler_header_key, profile.url)
  end

  defp before_send_profile(conn, endpoint, config, start_time) do
    register_before_send(conn, fn conn ->
      # todo: look for exceptions in the conn
      telemetry_execute(conn, :stop, %{duration: System.monotonic_time() - start_time})

      case PhoenixProfiler.Profiler.collect(
             conn.private.phoenix_profiler,
             conn.private.phoenix_profiler_collector
           ) do
        {:ok, profile} ->
          conn = apply_profile_headers(conn, profile)
          true = PhoenixProfiler.Profiler.insert_profile(profile)
          maybe_inject_debug_toolbar(conn, profile, endpoint, config)

        :error ->
          conn
      end
    end)
  end

  defp telemetry_execute(%Plug.Conn{} = conn, action, measurements)
       when action in [:start, :stop] do
    :telemetry.execute([:phoenix_profiler, :plug, action], measurements, %{conn: conn})
    conn
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
  # https://github.com/phoenixframework/phoenix_live_reload/blob/564ab19d54f2476a6c43d43beeb3ed2807f453c0/lib/phoenix_live_reload/live_reloader.ex#L129
  defp inject_debug_toolbar(conn, profile, endpoint, config) do
    resp_body = IO.iodata_to_binary(conn.resp_body)

    if has_body?(resp_body) and Code.ensure_loaded?(endpoint) do
      {head, [last]} = Enum.split(String.split(resp_body, "</body>"), -1)
      head = Enum.intersperse(head, "</body>")
      body = [head, debug_toolbar_assets_tag(conn, profile, config), "</body>" | last]
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

        attrs =
          Keyword.merge(
            toolbar_attrs,
            id: "pwdt#{profile.token}",
            class: "phxprof-toolbar",
            role: "region",
            name: "Phoenix Web Debug Toolbar"
          )

        # Note: if the session keys change then you must bump the version:
        ToolbarView
        |> Phoenix.View.render("index.html", %{
          conn: conn,
          session: %{
            "vsn" => 1,
            "node" => profile.node,
            "server" => profile.server,
            "token" => profile.token
          },
          token: profile.token,
          toolbar_attrs: attrs
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
end
