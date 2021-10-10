defmodule DemoWeb.PageController do
  use DemoWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def hello(conn, %{"name" => name}) do
    render(conn, "hello.html", name: name)
  end

  def hello(conn, _params) do
    render(conn, "hello.html", name: "friend")
  end
end
