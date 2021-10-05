defmodule PhoenixWeb.Debug.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :phoenix_web_debug,
    pubsub_server: PhoenixWeb.Debug.PubSub
end
