defmodule DemoWeb.PageView do
  use DemoWeb, :view
  use Phoenix.Component

  def render("index.html", assigns) do
    ~H"""
    <h1>Phoenix Web Profiler Dev</h1>
    <p>Welcome, devs!</p>
    <h2>Links</h2>
    <ul>
      <li><%= link "Profile IndexController, :hello", to: Routes.page_path(DemoWeb.Endpoint, :hello) %></li>
      <li><%= link "Profile ErrorView: assign not available", to: Routes.errors_path(DemoWeb.Endpoint, :assign_not_available) %></li>
      <li><%= link "Profile AppLive.Index, :index", to: Routes.app_index_path(DemoWeb.Endpoint, :index) %></li>
    </ul>
    """
  end

  def render("hello.html", assigns) do
    ~H"""
    <hello>Hello, <%= @name %>!</hello>
    """
  end
end
