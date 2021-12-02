defmodule PhoenixWeb.Profiler.Application do
  @moduledoc false

  use Application
  alias PhoenixWeb.Profiler

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: PhoenixProfiler.DynamicSupervisor},
      Profiler.Requests
    ]

    opts = [strategy: :one_for_one, name: Profiler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
