defmodule PhoenixProfiler.Supervisor do
  @moduledoc false
  use Supervisor
  alias PhoenixProfiler.Profiler
  alias PhoenixProfiler.Telemetry
  alias PhoenixProfiler.Utils

  def start_link(opts) do
    {name, opts} = opts |> Enum.into([]) |> Keyword.pop(:name)

    unless name do
      raise ArgumentError, "the :name option is required to start PhoenixProfiler"
    end

    Supervisor.start_link(__MODULE__, {name, opts}, name: name)
  end

  def init({name, opts}) do
    system = Utils.system()
    table = :ets.new(name, [:set, :public, {:write_concurrency, true}])

    :persistent_term.put({PhoenixProfiler, name}, %Profiler{
      system: system,
      tab: table
    })

    children = [
      {Profiler, {name, table, opts}},
      {Telemetry, [{:name, debug_name(name)} | opts]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def store_name(name) do
    Module.concat([PhoenixProfiler, :"#{name}", :ProfileStore])
  end

  def debug_name(name) do
    Module.concat([PhoenixProfiler, :"#{name}", :Telemetry])
  end
end
