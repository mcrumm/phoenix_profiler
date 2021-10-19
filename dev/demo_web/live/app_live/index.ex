defmodule User do
  defstruct [:id, :name]
end

defmodule DemoWeb.AppLive.Index do
  use DemoWeb, :live_view

  def mount(_, _, socket) do
    {:ok, assign(socket, count: 0, user: %User{id: 1, name: "José"})}
  end

  def render(assigns) do
    ~L"""
    <section class="live">
      <h2>AppLive Page</h2>
      <p>Action=<%= @live_action %></p>
      <button phx-click="plus">+</button><button phx-click="minus">-</button>
      <p>count=<%= @count %></p>
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
