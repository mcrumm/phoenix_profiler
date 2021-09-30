if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule FriendsOfPhoenix.LiveDebug do
    @moduledoc """
    Inject debug tools into a LiveView process.

    ## Configuration

    Add it to your `:live_view` callback in your `_web.ex` module:

          def live_view do
            quote do
              use Phoenix.LiveView,
                layout: {HelloWeb.LayoutView, "live.html"}

              # Add this block to your LiveView
              if Mix.env() == :dev do
                on_mount {FriendsOfPhoenix.Debug, __MODULE__}
              end

              unquote(view_helpers())
            end
          end

    Or, you can put it directly on a LiveView module:

          defmodule HelloLive do
            use Phoenix.LiveView
            if Mix.env() == :dev, do: on_mount({FriendsOfPhoenix.Debug, __MODULE__})

          end


    """
    import Phoenix.LiveView
    alias FriendsOfPhoenix.Debug

    @session_key "fophx_debug"

    def on_mount(view_module, params, %{@session_key => token} = session, socket) do
      apply_debug_hooks(socket, connected?(socket), view_module, token, params, session)
    end

    def on_mount(_view_module, _params, _session, socket) do
      {:cont, socket}
    end

    defp apply_debug_hooks(socket, _connected? = false, _view_module, _token, _params, _session) do
      {:cont, socket}
    end

    defp apply_debug_hooks(socket, _connected? = true, view_module, token, _params, _session) do
      Debug.put_entry(token, __MODULE__, %{
        phoenix_live_action: socket.assigns.live_action,
        root_view: socket.private[:root_view],
        transport_pid: transport_pid(socket),
        view_pid: self(),
        view_module: view_module
      })

      socket
      |> put_private(Debug, %{token: token})
      |> attach_hook(Debug, :handle_info, &on_handle_info/2)
      |> attach_hook(Debug, :handle_params, &on_handle_params/3)

      {:cont, socket}
    end

    defp put_private(%{private: private} = socket, key, value) do
      %{socket | private: Map.put(private, key, value)}
    end

    defp on_handle_info(
           {Debug, token, from, msg},
           %{private: %{Debug => %{token: token}}} = socket
         ) do
      IO.inspect(msg, label: "Message from #{inspect(from)}")
      {:cont, socket}
    end

    defp on_handle_info(_, socket) do
      {:cont, socket}
    end

    defp on_handle_params(_params, _uri, socket) do
      {:cont, socket}
    end
  end
end
