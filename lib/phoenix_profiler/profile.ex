defmodule PhoenixProfiler.Profile do
  # An internal data structure for a request profile.
  @moduledoc false
  defstruct [
    :info,
    :node,
    :server,
    :start_time,
    :system_time,
    :token,
    :url
  ]

  @type info :: nil | :enable | :disable

  @type t :: %__MODULE__{
          :info => info(),
          :token => String.t(),
          :server => module(),
          :node => node(),
          :start_time => integer(),
          :system_time => integer(),
          :url => String.t()
        }

  @doc """
  Returns a new profile.
  """
  def new(node \\ node(), server, token, info, base_url, system_time)
      when is_atom(server) and is_binary(token) and
             is_atom(info) and info in [nil, :enable, :disable] and
             is_binary(base_url) and is_integer(system_time) do
    %__MODULE__{
      info: info,
      node: node,
      server: server,
      start_time: System.monotonic_time(),
      system_time: system_time,
      token: token,
      url: build_url(server, token, base_url)
    }
  end

  defp build_url(server, token, base_url) do
    params = %{nav: inspect(server), panel: :request, token: token}
    base_url <> "?" <> URI.encode_query(params)
  end
end
