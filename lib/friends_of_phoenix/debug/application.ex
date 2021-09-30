defmodule FriendsOfPhoenix.Debug.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: FriendsOfPhoenix.Debug.DynamicSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: FriendsOfPhoenix.Debug.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
