defmodule FriendsOfPhoenix.Debug.View do
  # Acts as a View for toolbar layout rendering
  @moduledoc false
  import Phoenix.LiveView.Helpers
  alias FriendsOfPhoenix.Debug

  toolbar_css_path = Application.app_dir(:fophx_debug, "priv/static/toolbar.css")
  @external_resource toolbar_css_path

  @toolbar_css File.read!(toolbar_css_path)

  def render("toolbar.html", assigns) do
    assigns = Map.put(assigns, :toolbar_css, @toolbar_css)

    ~L"""
    <div <%= Phoenix.HTML.raw(@toolbar_attrs) %>>
      <!-- START Phoenix Web Debug Toolbar -->
    <div id="phxweb-toolbar-clearer-<%= @token %>" class="phxweb-toolbar-clearer" style="display: block;"></div>
    <%= live_render(@conn, Debug.ToolbarLive, session: @session) %>
      <!-- END Phoenix Web Debug Toolbar -->
    </div>
    <style type="text/css"><%= Phoenix.HTML.raw(@toolbar_css) %></style>
    """
  end
end
