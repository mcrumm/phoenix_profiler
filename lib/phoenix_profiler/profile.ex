defmodule PhoenixProfiler.Profile do
  # An internal data structure for a request profile.
  @moduledoc false
  defstruct [
    :endpoint,
    :info,
    :node,
    :start_time,
    :system,
    :system_time,
    :token,
    :url
  ]

  @type info :: nil | :enable | :disable

  @type system :: %{
          :otp => String.t(),
          :elixir => String.t(),
          :phoenix => String.t(),
          :phoenix_profiler => String.t(),
          required(atom()) => nil | String.t()
        }

  @type t :: %__MODULE__{
          :endpoint => module(),
          :info => info(),
          :token => String.t(),
          :node => node(),
          :start_time => integer(),
          :system => system(),
          :system_time => integer(),
          :url => String.t()
        }

  @doc """
  Returns a new profile.
  """
  def new(node \\ node(), endpoint, token, info, base_url, system_time)
      when is_atom(endpoint) and is_binary(token) and
             is_atom(info) and info in [nil, :enable, :disable] and
             is_binary(base_url) and is_integer(system_time) do
    %__MODULE__{
      endpoint: endpoint,
      info: info,
      node: node,
      start_time: System.monotonic_time(),
      system: PhoenixProfiler.system(),
      system_time: system_time,
      token: token,
      url: build_url(endpoint, token, base_url)
    }
  end

  defp build_url(endpoint, token, base_url) do
    params = %{nav: inspect(endpoint), panel: :request, token: token}
    base_url <> "?" <> URI.encode_query(params)
  end
end
