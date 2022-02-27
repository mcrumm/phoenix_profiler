defmodule PhoenixProfiler.Profile do
  # An internal data structure for a request profile.
  @moduledoc false
  defstruct [
    :data,
    :node,
    :server,
    :system,
    :system_time,
    :token,
    :url
  ]

  @type system :: %{
          :otp => String.t(),
          :elixir => String.t(),
          :phoenix => String.t(),
          :phoenix_profiler => String.t(),
          required(atom()) => nil | String.t()
        }

  @type t :: %__MODULE__{
          :data => map(),
          :token => String.t(),
          :server => module(),
          :node => node(),
          :system => system(),
          :system_time => integer(),
          :url => String.t()
        }

  @doc """
  Returns a new profile.
  """
  def new(server, token, base_url, system_time)
      when is_atom(server) and is_binary(token) and
             is_binary(base_url) and is_integer(system_time) do
    %__MODULE__{
      node: node(),
      server: server,
      system: PhoenixProfiler.ProfileStore.system(server),
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
