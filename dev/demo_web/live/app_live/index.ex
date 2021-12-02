defmodule DemoWeb.AppLive.Index do
  use DemoWeb, :live_view

  def mount(_, _, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  def render(assigns) do
    ~L"""
    <section class="live">
      <h2>AppLive Page</h2>
      <p>Action=<%= @live_action %></p>
      <p>Count=<%= @count %></p>
      <button phx-click="plus">+</button><button phx-click="minus">-</button>
      <p>Links:</p>
      <ul>
        <li><%= live_redirect "Navigate to :index", to: Routes.app_index_path(@socket, :index) %></li>
        <li><%= live_redirect "Navigate to :foo", to: Routes.app_index_path(@socket, :foo) %></li>
      </ul>
    </section>
    """
  end

  def handle_event("plus", _, socket) do
    {:noreply,
     update(socket, :count, fn i ->
       i = i + 1
       dump(i)
       i
     end)}
  end

  def handle_event("minus", _, socket) do
    {:noreply,
     update(socket, :count, fn i ->
       i = i - 1
       dump(i)
       i
     end)}
  end
end
