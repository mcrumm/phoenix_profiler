defmodule PhoenixWeb.Profiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias PhoenixWeb.Profiler.{Dumped, Request, View}
  require Logger

  @doc """
  Dump the contents of a given `var` to the profiler.

  ## Examples

      dump(42)
      dump("Hello world")
      dump(@some_assign)

  """
  defmacro dump(var) do
    maybe_dump(var, __CALLER__)
  end

  # TODO: enable compile-time purging via configuration
  defp maybe_dump(var, caller) do
    %{file: file, line: line, module: module, function: function} = caller
    caller = [file: file, line: line, module: module, function: function]

    quoted_metadata =
      quote do
        unquote(caller)
      end

    quote do
      PhoenixWeb.Profiler.__dump_var__(
        unquote(var),
        unquote(quoted_metadata)
      )
    end
  end

  def __dump_var__(value, file: file, line: line, module: module, function: function) do
    Dumped.update(&[{value, file, line, module, function} | &1])

    # we could return a %Dumped{} that implements (L|H)eex protocols.
    # whatever we decide to return, we need to ensure it will render empty
    # because it will be invoked from within templates.
    nil
  end

  @behaviour Plug

  ## Plug API

  @impl Plug
  def init(opts) do
    toolbar_attrs =
      case opts[:toolbar_attrs] do
        attrs when is_list(attrs) -> attrs
        _ -> []
      end

    %{
      toolbar_attrs: toolbar_attrs
    }
  end

  # TODO: remove this clause when we add config for profiler except_patterns
  @impl Plug
  def call(%Plug.Conn{path_info: ["phoenix", "live_reload", "frame" | _suffix]} = conn, _) do
    # this clause is to ignore the phoenix live reload iframe in case someone installs
    # the toolbar plug above the LiveReloader plug in their Endpoint.
    conn
  end

  @impl Plug
  def call(conn, config) do
    endpoint = conn.private.phoenix_endpoint
    endpoint_config = endpoint.config(:phoenix_web_profiler)

    if endpoint_config do
      start_time = System.monotonic_time()

      conn
      |> Request.apply_debug_token()
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
    :telemetry.execute([:phxweb, :profiler, action], measurements, %{conn: conn})
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
      if Code.ensure_loaded?(PhoenixWeb.Profiler.ToolbarLive) do
        token = Request.debug_token!(conn)
        motion_class = if System.get_env("PHOENIX_WEB_PROFILER_REDUCED_MOTION"), do: "no-motion"

        attrs =
          Keyword.merge(
            config.toolbar_attrs,
            id: Request.toolbar_id(conn),
            class: String.trim("phxweb-toolbar #{motion_class}"),
            role: "region",
            name: "Phoenix Web Debug Toolbar"
          )

        View
        |> Phoenix.View.render("toolbar.html", %{
          conn: conn,
          session: %{"token" => token, "node" => node()},
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

  # Unique ID generation
  # Copyright (c) 2013 Plataformatec.
  # https://github.com/elixir-plug/plug/blob/fb6b952cf93336dc79ec8d033e09a424d522ce56/lib/plug/request_id.ex
  @doc false
  def random_unique_id do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end
end
