defmodule DemoWeb.ErrorsController do
  use DemoWeb, :controller

  def assign_not_available(conn, _) do
    render(conn, "assign_not_available.html", %{})
  end
end

defmodule DemoWeb.ErrorsView do
  use DemoWeb, :view

  def render("assign_not_available.html", assigns) do
    ~E"""
    <p><%= @not_available %></p>
    """
  end
end
