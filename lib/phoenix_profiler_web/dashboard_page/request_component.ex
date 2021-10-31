if Code.ensure_loaded?(Phoenix.LiveDashboard) do
  defmodule PhoenixWeb.Profiler.DashboardPage.RequestComponent do
    @moduledoc false
    use Phoenix.LiveComponent

    @impl true
    def render(%{profile: _} = assigns) do
      ~L"""
      <div>
        <p>This is the request component!</p>
        <p>The token is: <kbd><%= @profile.conn.private.pwdt %></kbd></p>
        <pre><code><%= inspect(Map.delete(assigns, :socket), pretty: true, limit: :infinity) %></code></pre>
      </div>
      """
    end
  end
end
