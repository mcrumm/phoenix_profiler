defmodule PhoenixWeb.Profiler.View do
  # Acts as a View for toolbar layout rendering
  @moduledoc false
  import Phoenix.LiveView.Helpers
  alias PhoenixWeb.Profiler

  toolbar_css_path = Application.app_dir(:phoenix_web_profiler, "priv/static/toolbar.css")
  @external_resource toolbar_css_path

  @toolbar_css File.read!(toolbar_css_path)

  def render("toolbar.html", assigns) do
    assigns = Map.put(assigns, :toolbar_css, @toolbar_css)

    ~L"""
    <div <%= Phoenix.HTML.raw(@toolbar_attrs) %>>
      <!-- START Phoenix Web Profiler Toolbar -->
    <div id="phxweb-toolbar-clearer-<%= @token %>" class="phxweb-toolbar-clearer" style="display: block;"></div>
    <%= live_render(@conn, Profiler.ToolbarLive, session: @session) %>
      <!-- END Phoenix Web Profiler Toolbar -->
    </div>
    <style type="text/css"><%= Phoenix.HTML.raw(@toolbar_css) %></style>
    """
  end
end
