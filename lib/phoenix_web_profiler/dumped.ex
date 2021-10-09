defmodule PhoenixWeb.Profiler.Dumped do
  # Operations over the dumped contents.
  # Dumps are stored in the process dictionary until flushed.
  # @moduledoc false

  @content_key :phxweb_profiler_dumped

  @doc """
  Flushes the dumped contents.

  ## Examples

      iex(1)> PhoenixWeb.Profiler.Dumped.flush()
      []
      iex(2)> PhoenixWeb.Profiler.Dumped.push(:a)
      iex(3)> PhoenixWeb.Profiler.Dumped.push(:b)
      iex(4)> PhoenixWeb.Profiler.Dumped.flush()
      [:b, :a]
      iex(5)> PhoenixWeb.Profiler.Dumped.flush()
      []

  """
  def flush, do: set([]) || []

  @doc """
  Pushes a dump on to the top of the Dumped.

  ## Examples

      iex> PhoenixWeb.Profiler.Dumped.push(:a)
      [:a]

  """
  def push(content), do: update(&[content | &1])

  @doc """
  Updates the Dumped.

  ## Examples

      iex> PhoenixWeb.Profiler.Dumped.update(&[:foo | &1])
      [:foo]

      iex> PhoenixWeb.Profiler.Dumped.update(&[:bar, | &1])
      [:bar, :foo]

  """
  def update(fun), do: get() |> fun.() |> set()

  defp get, do: Process.get(@content_key, [])
  defp set(stack) when is_list(stack), do: Process.put(@content_key, stack)
end
