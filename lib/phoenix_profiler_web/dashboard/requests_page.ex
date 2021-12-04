if Code.ensure_loaded?(Phoenix.LiveDashboard) do
  defmodule PhoenixProfilerWeb.RequestsPage do
    # LiveDashboard integration for PhoenixProfiler.
    @moduledoc false
    use Phoenix.LiveDashboard.PageBuilder
    alias PhoenixProfiler.Requests

    @impl true
    def init(_) do
      {:ok, %{}, [{:application, :phoenix_profiler}]}
    end

    @impl true
    def menu_link(_session, _capabilities) do
      {:ok, "PhoenixProfiler"}
    end

    @impl true
    def handle_params(params, _uri, socket) do
      socket =
        if token = params["token"] do
          profile = Requests.remote_get(socket.assigns.page.node, token)
          assign(socket, :profile, profile)
        else
          socket
        end

      {:noreply, socket}
    end

    @impl true
    def render_page(assigns) do
      nav_bar(
        items: [
          {:profiler,
           name: "Requests",
           method: :redirect,
           render: fn ->
             if assigns[:profile] do
               conn = assigns.profile.conn

               nav_bar(
                 items: [
                   path_params: [
                     name: "Path Params",
                     render: fn -> render_params_table(conn, :path_params) end
                   ],
                   query_params: [
                     name: "Query Params",
                     render: fn -> render_params_table(conn, :query_params) end
                   ],
                   body_params: [
                     name: "Body Params",
                     render: fn -> render_params_table(conn, :body_params) end
                   ],
                   request_headers: [
                     name: "Request Headers",
                     render: fn -> render_params_table(conn, :req_headers, "Request Headers") end
                   ],
                   request_cookies: [
                     name: "Request Cookies",
                     render: fn -> render_params_table(conn, :req_cookies, "Request Cookies") end
                   ],
                   response_headers: [
                     name: "Response Headers",
                     render: fn ->
                       render_params_table(conn, :resp_headers, "Response Headers")
                     end
                   ],
                   response_cookies: [
                     name: "Response Cookies",
                     render: fn ->
                       render_params_table(conn, :resp_cookies, "Response Cookies")
                     end
                   ],
                   private: [
                     name: "Private",
                     render: fn -> render_params_table(conn, :private) end
                   ]
                 ],
                 extra_params: [:endpoint, :token]
               )
             else
               table(
                 columns: columns(),
                 id: :phxprof_requests_table,
                 row_attrs: &row_attrs/1,
                 row_fetcher: &fetch_profiles/2,
                 rows_name: "requests",
                 title: "Requests"
               )
             end
           end}
        ],
        style: :bar
      )
    end

    defp render_params_table(conn, field, title \\ nil) do
      table(
        id: :"#{field}_table",
        columns: [
          %{
            field: :key,
            sortable: :asc
          },
          %{
            field: :value,
            sortable: nil
          }
        ],
        row_fetcher: fn _params, _node ->
          rows =
            case Map.get(conn, field) do
              %Plug.Conn.Unfetched{} ->
                []

              params when is_map(params) or is_list(params) ->
                for {key, value} <- params,
                    do: %{key: pp(key), value: pp(value)}
            end

          {rows, length(rows)}
        end,
        title: title || Phoenix.Naming.humanize(field)
      )
    end

    # for printing
    defp pp(val) when is_binary(val) or is_number(val), do: val
    defp pp(val), do: inspect(val)

    @impl true
    def handle_event("show_profile", %{"token" => token}, socket) do
      token_path = live_dashboard_path(socket, socket.assigns.page, %{token: token})

      {:noreply, push_redirect(socket, to: token_path)}
    end

    defp fetch_profiles(params, node) do
      %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

      {profiles, total} = fetch_profiles(node, search, sort_by, sort_dir, limit)

      rows =
        for {token, prof} <- profiles do
          %{at: at, conn: %Plug.Conn{} = conn} = prof

          conn
          |> Map.take([:host, :status, :method, :remote_ip])
          |> Map.put(:url, Plug.Conn.request_url(conn))
          |> Map.put(:token, token)
          |> Map.put(:at, at)
        end

      {rows, total}
    end

    defp fetch_profiles(node, search, sort_by, sort_dir, limit) do
      profiles = Requests.remote_list_advanced(node, search, sort_by, sort_dir, limit)
      {profiles, length(profiles)}
    end

    defp columns do
      [
        %{
          field: :status,
          sortable: nil
        },
        %{
          field: :remote_ip,
          header: "IP",
          format: &:inet.ntoa/1
        },
        %{
          field: :method
        },
        %{
          field: :url,
          header: "URL"
        },
        %{
          field: :at,
          header: "Profiled at",
          sortable: :desc,
          format: &format_time/1
        },
        %{
          field: :token,
          format: &format_token/1
        }
      ]
    end

    defp row_attrs(row) do
      [
        {"phx-click", "show_profile"},
        {"phx-value-token", row.token},
        {"phx-page-loading", true}
      ]
    end

    defp format_token(token) do
      # TODO: convert to a link
      token
    end

    defp format_time(at) do
      at
      |> System.convert_time_unit(:native, :second)
      |> DateTime.from_unix!()
    end
  end
end
