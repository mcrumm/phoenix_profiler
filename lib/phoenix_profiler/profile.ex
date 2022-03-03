defmodule PhoenixProfiler.Profile do
  # An internal data structure for a request profile.
  @moduledoc false
  defstruct [
    :endpoint,
    :info,
    :node,
    :server,
    :system,
    :system_time,
    :token,
    :url,
    data: %{}
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
          :endpoint => module(),
          :info => nil | :disable | :enable,
          :token => String.t(),
          :server => module(),
          :node => node(),
          :system => system(),
          :system_time => nil | integer(),
          :url => String.t()
        }

  @doc """
  Returns a new profile.
  """
  def new(endpoint, server, token, base_url, info)
      when is_atom(endpoint) and is_atom(server) and
             is_binary(token) and is_binary(base_url) and
             is_atom(info) do
    params = %{nav: inspect(server), panel: :request, token: token}
    url = base_url <> "?" <> URI.encode_query(params)

    %__MODULE__{
      endpoint: endpoint,
      info: info,
      node: node(),
      server: server,
      system: PhoenixProfiler.ProfileStore.system(server),
      token: token,
      url: url
    }
  end
end
