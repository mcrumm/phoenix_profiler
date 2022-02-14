defmodule PhoenixProfiler.Supervisor do
  @moduledoc false
  use Supervisor
  alias PhoenixProfiler.Profiler
  alias PhoenixProfiler.Telemetry
  alias PhoenixProfiler.TelemetryServer

  def start_link(opts) do
    {name, opts} = opts |> Enum.into([]) |> Keyword.pop(:name)

    unless name do
      raise ArgumentError, "the :name option is required to start PhoenixProfiler"
    end

    Supervisor.start_link(__MODULE__, {name, opts}, name: name)
  end

  def init({name, opts}) do
    events = (opts[:telemetry] || []) ++ Telemetry.events()

    children = [
      {Profiler, {name, opts}},
      {TelemetryServer, [filter: &Telemetry.collect/4, server: name, events: events]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
