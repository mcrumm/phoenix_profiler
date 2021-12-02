defmodule PhoenixProfiler.Utils do
  @moduledoc false
  alias Phoenix.LiveView

  def put_private(%LiveView.Socket{} = socket, key, value) when is_atom(key) do
    private = Map.put(socket.private, key, value)
    %{socket | private: private}
  end
end
