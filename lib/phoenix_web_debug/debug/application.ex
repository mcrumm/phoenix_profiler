defmodule PhoenixWeb.Debug.Application do
  @moduledoc false

  use Application
  alias PhoenixWeb.Debug

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Debug.PubSub},
      Debug.Presence,
      {DynamicSupervisor, name: Debug.DynamicSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Debug.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
