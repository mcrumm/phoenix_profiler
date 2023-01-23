defmodule PhoenixProfiler.ProfileStore do
  # Helpers for fetching profile data from local and remote nodes.
  @moduledoc false
  alias PhoenixProfiler.Profile
  alias PhoenixProfiler.Utils

  @doc """
  Returns the profiler for a given `conn` if it exists.
  """
  def profiler(%Plug.Conn{} = conn) do
    case conn.private[:phoenix_profiler] do
      %Profile{server: server} when is_atom(server) -> server
      nil -> nil
    end
  end

  @doc """
  Returns the profile for a given `token` if it exists.
  """
  def get(token) do
    case PhoenixProfiler.Server.lookup_entries(token) do
      [] ->
        nil

      entries ->
        Enum.reduce(entries, %{metrics: %{endpoint_duration: nil}}, fn
          {^token, _event, _event_ts, %{endpoint_duration: duration}}, acc ->
            %{acc | metrics: Map.put(acc.metrics, :endpoint_duration, duration)}

          {^token, _event, _event_ts, %{metrics: _} = entry}, acc ->
            {metrics, rest} = PhoenixProfiler.Utils.map_pop!(entry, :metrics)
            acc = Map.merge(acc, rest)
            %{acc | metrics: Map.merge(acc.metrics, metrics)}

          {^token, _event, _event_ts, data}, acc ->
            Map.merge(acc, data)
        end)
    end
  end

  @doc """
  Returns all profiles for a given `profiler`.
  """
  def list(profiler) do
    :ets.tab2list(tab(profiler))
  end

  @doc """
  Returns a filtered list of profiles.
  """
  def list_advanced(profiler, _search, sort_by, sort_dir, _limit) do
    Utils.sort_by(list(profiler), fn {_, profile} -> profile[sort_by] end, sort_dir)
  end

  @doc """
  Fetches a profile on a remote node.
  """
  def remote_get(%Profile{} = profile) do
    remote_get(profile.node, profile.server, profile.token)
  end

  def remote_get(node, _profiler, token) do
    :rpc.call(node, __MODULE__, :get, [token])
  end

  @doc """
  Returns a filtered list of profiles on a remote node.
  """
  def remote_list_advanced(node, profiler, search, sort_by, sort_dir, limit) do
    :rpc.call(node, __MODULE__, :list_advanced, [profiler, search, sort_by, sort_dir, limit])
  end

  @doc """
  Returns the ETS table for a given `profile`.
  """
  def table(%Profile{server: profiler} = _profile) do
    tab(profiler)
  end

  defp tab(_profiler) do
    PhoenixProfiler.Server.Profile
  end
end
