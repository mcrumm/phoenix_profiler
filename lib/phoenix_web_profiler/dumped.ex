defmodule PhoenixWeb.Profiler.Dumped do
  # Operations over the dumped contents.
  # Dumps are stored in the process dictionary until flushed.
  @moduledoc false

  @content_key :phxweb_profiler_dumped

  @doc """
  Flushes the dumped contents.

  ## Examples

      iex(1)> PhoenixWeb.Profiler.Dumped.flush()
      []
      iex(2)> PhoenixWeb.Profiler.Dumped.push(:a)
      []
      iex(3)> PhoenixWeb.Profiler.Dumped.push(:b)
      [:a]
      iex(4)> PhoenixWeb.Profiler.Dumped.push(:c)
      [:b, :a]
      iex(5)> PhoenixWeb.Profiler.Dumped.flush()
      [:c, :b, :a]

  """
  def flush, do: set([]) || []

  @doc """
  Pushes the given `content` on to the dumped contents on the current process.

  ## Examples

      iex(1)> PhoenixWeb.Profiler.Dumped.push(:a)
      []
      iex(2)> PhoenixWeb.Profiler.Dumped.peek()
      [:a]
  """
  def push(content), do: update(&[content | &1])

  @doc """
  Peeks at the dumped contents on the current process.

  ## Examples

      iex(1)> PhoenixWeb.Profiler.Dumped.peek()
      []
      iex(2)> PhoenixWeb.Profiler.Dumped.push(:a)
      []
      iex(3)> PhoenixWeb.Profiler.Dumped.peek()
      [:a]
  """
  def peek, do: get()

  @doc """
  Updates the dumped contents on the current process.

  ## Examples

      iex(1)> PhoenixWeb.Profiler.Dumped.update(&[:foo | &1])
      []
      iex(2)> PhoenixWeb.Profiler.Dumped.update(&[:bar | &1])
      [:foo]
      iex(3)> PhoenixWeb.Profiler.Dumped.update(& &1)
      [:bar, :foo]

  """
  def update(fun), do: get() |> fun.() |> set()

  defp get, do: Process.get(@content_key, [])
  defp set(stack) when is_list(stack), do: Process.put(@content_key, stack) || []
end
