defmodule DemoWeb.PlugRouter do
  use Plug.Router
  import Phoenix.Controller

  plug :match
  plug :dispatch

  get "/" do
    html(conn, "<html><body>PlugRouter::Home</body></html>")
  end

  match _ do
    html(conn, "<html><body>PlugRouter::Not Found</body></html>")
  end
end
