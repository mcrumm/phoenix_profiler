# Copyright (c) 2021 Chris McCord
# https://github.com/phoenixframework/phoenix/blob/aa9e708fec303f1114b9aa9c41a32a3f72c8a06c/test/support/endpoint_helper.exs
defmodule PhoenixProfiler.Integration.EndpointHelper do
  @moduledoc """
  Utility functions for integration testing endpoints.
  """

  @doc """
  Finds `n` unused network port numbers.
  """
  def get_unused_port_numbers(n) when is_integer(n) and n > 1 do
    1..n
    # Open up `n` sockets at the same time, so we don't get
    # duplicate port numbers
    |> Enum.map(&listen_on_os_assigned_port/1)
    |> Enum.map(&get_port_number_and_close/1)
  end

  defp listen_on_os_assigned_port(_) do
    {:ok, socket} = :gen_tcp.listen(0, [])
    socket
  end

  defp get_port_number_and_close(socket) do
    {:ok, port_number} = :inet.port(socket)
    :gen_tcp.close(socket)
    port_number
  end

  @doc """
  Generates a signing salt for a LiveView configuration.
  """
  def gen_salt do
    gen_secret(8)
  end

  @doc """
  Generates a secret key base for an Endpoint configuration.
  """
  def gen_secret_key do
    gen_secret(64)
  end

  defp gen_secret(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64(padding: false)
    |> binary_part(0, length)
  end
end
