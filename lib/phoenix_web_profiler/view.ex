defmodule PhoenixWeb.Profiler.View do
  # Acts as a View for toolbar layout rendering
  @moduledoc false
  import Phoenix.LiveView.Helpers
  alias PhoenixWeb.Profiler

  toolbar_css_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.css")
  @external_resource toolbar_css_path

  toolbar_js_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.js")
  @external_resource toolbar_js_path

  @toolbar_css File.read!(toolbar_css_path)
  @toolbar_js File.read!(toolbar_js_path)

  def render("toolbar.html", assigns) do
    assigns = Map.put(assigns, :toolbar_css, @toolbar_css)
    assigns = Map.put(assigns, :toolbar_js, @toolbar_js)

    ~L"""
    <div<%= Phoenix.HTML.raw(@toolbar_attrs) %>>
      <!-- START Phoenix Web Debug Toolbar -->
    <div class="phxweb-minitoolbar"><button class="show-button" type="button" id="phx-web-toolbar-show-<%= @token %>>" title="Show Toolbar" accesskey="D" aria-expanded="true" aria-controls="phxweb-toolbar-main-<%= @token %>"></button></div>
    <div id="phxweb-toolbar-clearer-<%= @token %>" class="phxweb-toolbar-clearer" style="display: block;"></div>
    <%= live_render(@conn, Profiler.ToolbarLive, session: @session) %>
      <!-- END Phoenix Web Debug Toolbar -->
    </div>
    <script><%= Phoenix.HTML.raw(@toolbar_js) %></script>
    <style type="text/css"><%= Phoenix.HTML.raw(@toolbar_css) %></style>
    """
  end
end
