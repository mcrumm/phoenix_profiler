if Code.ensure_loaded?(Phoenix.LiveDashboard) do
  defmodule PhoenixWeb.Profiler.DashboardBridge do
    @moduledoc false
    use Phoenix.LiveDashboard.PageBuilder

    import Phoenix.LiveDashboard.Helpers

    @impl true
    def menu_link(_, _) do
      {:ok, "WebProfiler"}
    end

    @impl true
    def render_page(_assigns) do
      table(
        columns: columns(),
        id: :ets_table,
        row_attrs: &row_attrs/1,
        row_fetcher: &fetch_profiles/2,
        rows_name: "tables",
        title: "Profiles"
      )
    end

    defp fetch_profiles(params, node) do
      %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

      # Here goes the code that goes through all ETS tables, searches
      # (if not nil), sorts, and limits them.
      #
      # It must return a tuple where the first element is list with
      # the current entries (up to limit) and an integer with the
      # total amount of entries.
      # ...
      {[], 0}
    end

    defp columns do
      [
        %{
          field: :name,
          header: "Name or module"
        },
        %{
          field: :protection
        },
        %{
          field: :type
        },
        %{
          field: :size,
          cell_attrs: [class: "text-right"],
          sortable: :desc
        },
        %{
          field: :memory,
          format: &format_words(&1[:memory]),
          sortable: :desc
        },
        %{
          field: :owner,
          format: &encode_pid(&1[:owner])
        }
      ]
    end

    defp row_attrs(table) do
      [
        {"phx-click", "show_info"},
        {"phx-value-info", "???"},
        {"phx-page-loading", true}
      ]
    end
  end
end
