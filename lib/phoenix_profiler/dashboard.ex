if Code.ensure_loaded?(Phoenix.LiveDashboard) do
  defmodule PhoenixProfiler.Dashboard do
    @moduledoc """
    [`LiveDashboard`](`Phoenix.LiveDashboard`) integration for PhoenixProfiler.

    To use the profiler dashboard, add it to the
    `:additional_pages` of your
    [`live_dashboard`](`Phoenix.LiveDashboard.Router.live_dashboard/2`):

        live_dashboard "/dashboard",
          additional_pages: [
            _profiler: {#{inspect(__MODULE__)}, []}
            # additional pages...
          ]

    """
    use Phoenix.LiveDashboard.PageBuilder
    alias PhoenixProfiler.Utils
    alias PhoenixProfiler.Profiler

    @disabled_link "https://hexdocs.pm/phoenix_profiler"
    @page_title "Phoenix profilers"

    @impl true
    def init(opts) do
      profilers = opts[:profilers] || :auto_discover
      {:ok, %{profilers: profilers}, [{:application, :phoenix_profiler}]}
    end

    @impl true
    def menu_link(%{profilers: profilers}, _capabilities) do
      if profilers == [] do
        {:disabled, @page_title, @disabled_link}
      else
        {:ok, @page_title}
      end
    end

    defp profilers_or_auto_discover(profiler_config, node) do
      cond do
        profiler_config == [] ->
          {:error, :no_profilers_available}

        is_list(profiler_config) ->
          {:ok, profiler_config}

        profiler_config == :auto_discover ->
          running_profilers(node)

        true ->
          {:error, :no_profilers_available}
      end
    end

    defp running_profilers(node) do
      case :rpc.call(node, PhoenixProfiler, :all_running, []) do
        [] ->
          {:error, :no_profilers_available}

        profilers when is_list(profilers) ->
          {:ok, profilers}

        {:badrpc, _error} ->
          {:error, :cannot_list_running_profilers}
      end
    end

    @impl true
    def mount(params, %{profilers: profilers}, socket) do
      case profilers_or_auto_discover(profilers, socket.assigns.page.node) do
        {:ok, profilers} ->
          socket = assign(socket, :profilers, profilers)
          profiler = nav_profiler(params, profilers)

          case Utils.check_socket_connection(socket) do
            :ok -> {:ok, assign(socket, profiler: profiler, error: nil)}
            {:error, reason} -> {:ok, assign(socket, profiler: nil, error: reason)}
          end

        {:error, reason} ->
          {:ok, assign(socket, profiler: nil, error: reason)}
      end
    end

    defp nav_profiler(params, profilers) do
      nav = params["nav"]
      nav = if nav && nav != "", do: nav
      nav && Enum.find(profilers, fn name -> inspect(name) == nav end)
    end

    @impl true
    def handle_params(params, _uri, socket) do
      socket =
        if token = params["token"] do
          case Profiler.remote_get(socket.assigns.page.node, socket.assigns.profiler, token) do
            nil -> assign(socket, error: :token_not_found)
            profile -> assign(socket, profile: profile)
          end
        else
          socket
        end

      {:noreply, socket}
    end

    @impl true
    def render_page(assigns) do
      if assigns[:error] do
        render_error(assigns)
      else
        items =
          for name <- assigns.profilers do
            name = inspect(name)

            {name,
             name: name, render: fn -> render_profiler_or_error(assigns) end, method: :redirect}
          end

        nav_bar(items: items)
      end
    end

    defp render_profiler_or_error(assigns) do
      if assigns[:error] do
        render_error(assigns)
      else
        render_profile_or_profiles(assigns)
      end
    end

    defp render_profile_or_profiles(assigns) do
      if assigns[:profile] do
        render_profile_nav(assigns)
      else
        render_profiles_table(assigns)
      end
    end

    defp render_error(assigns) do
      error_message =
        case assigns.error do
          :todo ->
            "TODO"

          :waiting_for_connection ->
            "Waiting for connection..."

          :profiler_not_found ->
            "This profiler is not available for this node."

          :profiler_is_not_running ->
            "This profiler is not running on this node."

          :phoenix_profiler_is_not_available ->
            "PhoenixProfiler is not available on remote node."

          :no_profilers_available ->
            "There are no profilers running on this node."

          :cannot_list_running_profilers ->
            "Could not list running profilers at remote node. Please try again later."

          {:badrpc, _} ->
            "Could not send request to node. Try again later."

          :token_not_found ->
            "This token is not available for this profiler on this node."
        end

      {PhoenixProfiler.Dashboard.Error, %{error_message: error_message}}
    end

    defp render_profile_nav(assigns) do
      nav_bar(
        items: [
          request: [
            name: "Request / Response",
            render: fn -> render_panel(:request, assigns) end
          ]
        ],
        nav_param: :panel,
        extra_params: [:nav, :token]
      )
    end

    defp render_todo do
      render_error(%{error: :todo})
    end

    defp render_panel(:request, assigns) do
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
          session: [
            name: "Session",
            render: fn -> render_todo() end
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
          flashes: [
            name: "Flashes",
            render: fn -> render_todo() end
          ]
        ],
        nav_param: :tab,
        extra_params: [:nav, :panel, :token]
      )
    end

    defp render_profiles_table(assigns) do
      table(
        columns: columns(),
        id: :phxprof_requests_table,
        row_attrs: &row_attrs/1,
        row_fetcher: fn params, node -> fetch_profiles(params, assigns.profiler, node) end,
        rows_name: "requests",
        title: "Requests"
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
        row_fetcher: fn %{sort_by: sort_by, sort_dir: sort_dir}, _node ->
          rows =
            case Map.get(conn, field) do
              %Plug.Conn.Unfetched{} ->
                []

              params when is_map(params) or is_list(params) ->
                params = for {key, value} <- params, do: %{key: pp(key), value: pp(value)}
                Utils.sort_by(params, fn params -> params[sort_by] end, sort_dir)
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

    defp fetch_profiles(_, nil, _) do
      {[], 0}
    end

    defp fetch_profiles(params, profiler, node) do
      %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

      {profiles, total} = fetch_profiles(node, profiler, search, sort_by, sort_dir, limit)

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

    defp fetch_profiles(node, profiler, search, sort_by, sort_dir, limit) do
      profiles = Profiler.remote_list_advanced(node, profiler, search, sort_by, sort_dir, limit)
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
