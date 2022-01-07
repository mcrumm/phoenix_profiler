defmodule PhoenixProfiler.ToolbarView do
  # ToolbarView acts as a Phoenix.View rendering the embedded
  # web debug toolbar into an HTML response.
  @moduledoc false
  import Phoenix.LiveView.Helpers
  alias PhoenixProfiler.ToolbarLive

  toolbar_css_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.css")
  @external_resource toolbar_css_path

  toolbar_js_path = Application.app_dir(:phoenix_profiler, "priv/static/toolbar.js")
  @external_resource toolbar_js_path

  @toolbar_css File.read!(toolbar_css_path)
  @toolbar_js File.read!(toolbar_js_path)

  def render("index.html", assigns) do
    assigns = Map.put(assigns, :toolbar_css, @toolbar_css)
    assigns = Map.put(assigns, :toolbar_js, @toolbar_js)

    ~L"""
    <div<%= Phoenix.HTML.raw(@toolbar_attrs) %>>
      <!-- START Phoenix Web Debug Toolbar -->
    <div class="phxprof-minitoolbar"><button class="show-button" type="button" id="phxprof-toolbar-show-<%= @profile.token %>>" title="Show Toolbar" accesskey="D" aria-expanded="true" aria-controls="phxprof-toolbar-main-<%= @profile.token %>"></button></div>
    <div id="phxprof-toolbar-clearer-<%= @profile.token %>" class="phxprof-toolbar-clearer" style="display: block;"></div>
    <%= live_render(@conn, ToolbarLive, session: @session) %>
      <!-- END Phoenix Web Debug Toolbar -->
    </div>
    <script><%= Phoenix.HTML.raw(@toolbar_js) %></script>
    <style type="text/css"><%= Phoenix.HTML.raw(@toolbar_css) %></style>
    """
  end
end
