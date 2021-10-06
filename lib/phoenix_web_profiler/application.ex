defmodule PhoenixWeb.Profiler.Application do
  @moduledoc false

  use Application
  alias PhoenixWeb.Profiler

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Profiler.PubSub},
      Profiler.Presence,
      {DynamicSupervisor, name: Profiler.DynamicSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Profiler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
