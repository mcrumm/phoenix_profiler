defmodule PhoenixWeb.Profiler.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :phoenix_web_profiler,
    pubsub_server: PhoenixWeb.Profiler.PubSub
end
