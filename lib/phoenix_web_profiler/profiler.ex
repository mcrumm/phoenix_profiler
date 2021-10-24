defmodule PhoenixWeb.Profiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias PhoenixWeb.Profiler.{Dumped, Presence, Request, Session, View}
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

  @doc false
  def track(%Phoenix.LiveView.Socket{} = socket, session, meta)
      when is_map(session) and is_map(meta) do
    if Phoenix.LiveView.connected?(socket) do
      topic = Session.topic(session)
      key = Session.topic_key(session)

      {:ok, ref} =
        Presence.track(
          self(),
          topic,
          key,
          meta
          |> Map.put(:node, node())
          |> Map.put(:pid, self())
        )

      Phoenix.LiveView.assign(socket, :ref, ref)
    else
      socket
    end
  end

  @behaviour Plug
  @live_socket_path_default "/live"

  ## Plug API

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
    endpoint = conn.private.phoenix_endpoint
    endpoint_config = endpoint.config(:phoenix_web_profiler)

    if endpoint_config do
      conn
      |> Request.apply_debug_token()
      |> before_send_inject_debug_toolbar(endpoint, config)
    else
      conn
    end
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp before_send_inject_debug_toolbar(conn, endpoint, config) do
    register_before_send(conn, fn conn ->
      if conn.resp_body != nil and html?(conn) do
        resp_body = IO.iodata_to_binary(conn.resp_body)

        if has_body?(resp_body) and Code.ensure_loaded?(endpoint) do
          [page | rest] = String.split(resp_body, "</body>")

          body = [page, debug_toolbar_assets_tag(conn, endpoint, config), "</body>" | rest]
          conn = put_in(conn.resp_body, body)

          conn
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

  defp debug_toolbar_assets_tag(conn, _endpoint, config) do
    session =
      try do
        Session.live_session(conn)
      rescue
        RuntimeError ->
          require Logger

          Logger.debug("""
          #{inspect(__MODULE__)} could not be loaded because no session debug token was found.

          Did you remember to add #{inspect(__MODULE__)}.LiveProfiler to the
          :browser pipeline in your router? For example:

          pipeline :browser do
            # plugs...
            plug PhoenixWeb.LiveProfiler
          end
          """)

          nil
      end

    if session do
      attrs =
        Keyword.merge(
          config.toolbar_attrs,
          id: Request.toolbar_id(conn),
          class: "phxweb-toolbar",
          role: "region",
          name: "Phoenix Web Debug Toolbar"
        )

      View
      |> Phoenix.View.render("toolbar.html", %{
        conn: conn,
        session: session,
        token: Request.debug_token!(conn),
        toolbar_attrs: attrs(attrs)
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
    else
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
