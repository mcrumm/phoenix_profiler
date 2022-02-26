defmodule PhoenixProfiler.Profiler do
  @moduledoc false

  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.ProfileStore
  alias PhoenixProfiler.Utils

  @default_profiler_link_base "/dashboard/_profiler"

  @doc """
  Builds a profile from data collected for a given `conn`.
  """
  def collect(%Plug.Conn{} = conn) do
    endpoint = conn.private.phoenix_endpoint
    config = endpoint.config(:phoenix_profiler)

    link_base =
      case Keyword.fetch(config, :profiler_link_base) do
        {:ok, path} when is_binary(path) and path != "" ->
          "/" <> String.trim_leading(path, "/")

        _ ->
          @default_profiler_link_base
      end

    if conn.private.phoenix_profiler_info == :enable do
      time = System.system_time()

      data =
        PhoenixProfiler.TelemetryCollector.reduce(
          conn.private.phoenix_profiler_collector,
          %{metrics: %{endpoint_duration: nil}},
          fn
            {:telemetry, _, _, _, %{endpoint_duration: duration}}, acc ->
              %{acc | metrics: Map.put(acc.metrics, :endpoint_duration, duration)}

            {:telemetry, _, _, _, %{metrics: _} = entry}, acc ->
              {metrics, rest} = Utils.map_pop!(entry, :metrics)
              acc = Map.merge(acc, rest)
              %{acc | metrics: Map.merge(acc.metrics, metrics)}

            {:telemetry, _, _, _, data}, acc ->
              Map.merge(acc, data)
          end
        )

      profiler_base_url = endpoint.url() <> link_base

      profile =
        Profile.new(
          conn.private.phoenix_profiler,
          Utils.random_unique_id(),
          profiler_base_url,
          time
        )

      {:ok, %Profile{profile | data: data}}
    else
      :error
    end
  end

  @doc false
  def insert_profile(%Profile{} = profile) do
    profile
    |> ProfileStore.table()
    |> :ets.insert({profile.token, profile})
  end
end
