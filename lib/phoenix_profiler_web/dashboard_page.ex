if Code.ensure_loaded?(Phoenix.LiveDashboard) do
  defmodule PhoenixWeb.Profiler.DashboardPage do
    @moduledoc """
    Dashboard integration for the web profiler.

        live_dashboard "/dashboard",
          additional_pages: [
            _profiler: PhoenixWeb.Profiler.DashboardPage
            # additional pages...
          ]

    """
    use Phoenix.LiveDashboard.PageBuilder

    alias PhoenixWeb.Profiler.Requests

    @impl true
    def init(_) do
      {:ok, %{}, [{:application, :phoenix_web_profiler}]}
    end

    @impl true
    def menu_link(_session, _capabilities) do
      {:ok, "Phoenix Profiler"}
    end

    @impl true
    def handle_params(params, _uri, socket) do
      socket =
        if token = params["token"] do
          profile = Requests.fetch_token!(token)
          assign(socket, :profile, profile)
        else
          socket
        end

      {:noreply, socket}
    end

    @impl true
    def render_page(%{profile: profile}) do
      nav_bar(
        items: [
          request: [
            name: "Request",
            render: fn ->
              {PhoenixWeb.Profiler.DashboardPage.RequestComponent, %{profile: profile}}
            end
          ]
        ]
      )
    end

    def render_page(_assigns) do
      table(
        columns: columns(),
        id: :phxweb_profiler_profilers_table,
        row_attrs: &row_attrs/1,
        row_fetcher: &fetch_profiles/2,
        rows_name: "profiles",
        title: "Phoenix Profiler"
      )
    end

    @impl true
    def handle_event("show_profile", %{"token" => token}, socket) do
      token_path = live_dashboard_path(socket, socket.assigns.page, %{token: token})
      {:noreply, push_patch(socket, to: token_path)}
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
      :rpc.call(node, Requests, :profiles, [search, sort_by, sort_dir, limit])
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
