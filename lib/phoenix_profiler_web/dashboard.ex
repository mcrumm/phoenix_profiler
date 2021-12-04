defmodule PhoenixProfilerWeb.Dashboard do
  @moduledoc false

  @doc """
  Returns a page definition for LiveDashboard.
  """
  def dashboard(opts \\ []) do
    {PhoenixProfilerWeb.RequestsPage, opts}
  end
end
