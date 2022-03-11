# Copyright (c) 2014 Chris McCord
# https://github.com/phoenixframework/phoenix/blob/aa9e708fec303f1114b9aa9c41a32a3f72c8a06c/test/support/http_client.exs
defmodule PhoenixProfiler.Integration.HTTPClient do
  @doc """
  Performs HTTP Request and returns Response

    * method - The http method, for example :get, :post, :put, etc
    * url - The string url, for example "http://example.com"
    * headers - The map of headers
    * body - The optional string body. If the body is a map, it is converted
      to a URI encoded string of parameters

  ## Examples

      iex> HTTPClient.request(:get, "http://127.0.0.1", %{})
      {:ok, %Response{..})

      iex> HTTPClient.request(:post, "http://127.0.0.1", %{}, param1: "val1")
      {:ok, %Response{..})

      iex> HTTPClient.request(:get, "http://unknownhost", %{}, param1: "val1")
      {:error, ...}

  """
  def request(method, url, headers, body \\ "")

  def request(method, url, headers, body) when is_map(body) do
    request(method, url, headers, URI.encode_query(body))
  end

  def request(method, url, headers, body) do
    url = String.to_charlist(url)
    headers = headers |> Map.put_new("content-type", "text/html")
    ct_type = headers["content-type"] |> String.to_charlist()

    header =
      Enum.map(headers, fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)

    # Generate a random profile per request to avoid reuse
    profile = :crypto.strong_rand_bytes(4) |> Base.encode16() |> String.to_atom()
    {:ok, pid} = :inets.start(:httpc, profile: profile)

    resp =
      case method do
        :get -> :httpc.request(:get, {url, header}, [], [body_format: :binary], pid)
        _ -> :httpc.request(method, {url, header, ct_type, body}, [], [body_format: :binary], pid)
      end

    :inets.stop(:httpc, pid)
    format_resp(resp)
  end

  defp format_resp({:ok, {{_http, status, _status_phrase}, headers, body}}) do
    headers = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    {:ok, %{status: status, headers: headers, body: body}}
  end

  defp format_resp({:error, reason}), do: {:error, reason}

  @doc """
  Returns the values of the response header specified by `key`.

  ## Examples

      iex> req = %{req | headers: [{"content-type", "text/plain"}]}
      iex> HTTPClient.get_resp_header(req, "content-type")
      ["text/plain"]

  """
  def get_resp_header(%{headers: headers}, key) when is_list(headers) and is_binary(key) do
    for {^key, value} <- headers, do: value
  end
end
