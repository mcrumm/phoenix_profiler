defmodule PhoenixProfiler.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixProfiler.Server
    ]

    opts = [strategy: :one_for_one, name: PhoenixProfiler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
