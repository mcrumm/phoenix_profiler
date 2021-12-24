defmodule PhoenixProfilerWeb.Dashboard.Error do
  # TODO: Remove it when we support LiveDashboard v0.5+
  # A custom component to render an error on the dashboard.
  @moduledoc false
  use Phoenix.LiveComponent

  def render(assigns) do
    ~L"""
    <h2><%= @error_message %></h2>
    """
  end
end
