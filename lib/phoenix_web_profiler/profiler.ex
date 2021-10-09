defmodule PhoenixWeb.Profiler do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  import Plug.Conn
  alias PhoenixWeb.Profiler.{Presence, Server, Session, View}
  require Logger

  @dump_key :phxweb_profiler_dump

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
    %{file: file, line: line} = caller
    caller = [file: file, line: line]

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

  def __dump_var__(value, file: file, line: line) do
    update_dumped(&[{value, file, line} | &1])

    # we could return a %Dumped{} that implements (L|H)eex protocols.
    # whatever we decide to return, we need to ensure it will render empty
    # because it will be invoked from within templates.
    nil
  end

  defp get_dump, do: Process.get(@dump_key, [])
  defp put_dump(dump) when is_list(dump), do: Process.put(@dump_key, dump)
  defp retrieve_dump, do: put_dump([]) || []

  defp update_dumped(fun) do
    put_dump(fun.(get_dump()))
  end

  @doc false
  def track(%Phoenix.LiveView.Socket{} = socket, token, meta)
      when is_binary(token) and token != "" and is_map(meta) do
    if Phoenix.LiveView.connected?(socket) do
      {:ok, ref} =
        Presence.track(
          self(),
          Server.topic(token),
          inspect(self()),
          meta |> Map.put(:node, Node.self()) |> Map.put(:pid, self())
        )

      Phoenix.LiveView.assign(socket, :ref, ref)
    else
      socket
    end
  end

  @behaviour Plug

  @session_key :phxweb_debug_session
  @token_key :pwdt
  @token_header_key "x-debug-token"
  @live_socket_path_default "/live"

  @doc false
  def token_key, do: @token_key

  @doc false
  def session_key, do: @session_key

  defp profile_request(%Plug.Conn{} = conn, start_time) do
    # Measurements
    duration = System.monotonic_time() - start_time
    {:memory, bytes} = Process.info(self(), :memory)
    memory = div(bytes, 1_024)

    :ok =
      Session.profile_request(conn, %{
        dump: retrieve_dump(),
        duration: duration,
        memory: memory
      })

    put_resp_header(conn, @token_header_key, Session.session_token!(conn))
  end

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
    start_time = System.monotonic_time()

    conn
    |> Session.apply_debug_token()
    |> before_send_inject_debug_toolbar(conn.private.phoenix_endpoint, start_time, config)
  end

  # HTML Injection
  # Copyright (c) 2018 Chris McCord
  # https://github.com/phoenixframework/phoenix_live_reload/blob/ac73922c87fb9c554d03c5c466c2d62bf2216b0b/lib/phoenix_live_reload/live_reloader.ex
  defp before_send_inject_debug_toolbar(conn, endpoint, start_time, config) do
    register_before_send(conn, fn conn ->
      conn = profile_request(conn, start_time)

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
    {debug_token, session_token} = Session.tokens!(conn)

    attrs =
      Keyword.merge(
        config.toolbar_attrs,
        id: "pwdt#{debug_token}",
        class: "phxweb-toolbar",
        role: "region",
        name: "Phoenix Web Debug Toolbar"
      )

    View
    |> Phoenix.View.render("toolbar.html", %{
      conn: conn,
      session: %{
        to_string(@token_key) => debug_token,
        to_string(@session_key) => session_token
      },
      token: debug_token,
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
