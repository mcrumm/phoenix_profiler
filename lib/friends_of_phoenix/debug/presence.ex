defmodule FriendsOfPhoenix.Debug.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :fophx_debug,
    pubsub_server: FriendsOfPhoenix.Debug.PubSub
end
