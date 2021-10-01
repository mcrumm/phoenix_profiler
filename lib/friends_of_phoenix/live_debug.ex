defmodule FriendsOfPhoenix.LiveDebug do
  @moduledoc """
  Inject debug tools into a LiveView process.

  ## Configuration

  Add it to the `:live_view` function in your `_web.ex` module:

        # lib/hello_web.ex
        def live_view do
          quote do
            use Phoenix.LiveView,
              layout: {HelloWeb.LayoutView, "live.html"}

            # Add this block to your LiveView
            if Mix.env() == :dev do
              on_mount {#{inspect(__MODULE__)}, __MODULE__}
            end

            unquote(view_helpers())
          end
        end

  Or, you can put it directly on a LiveView module:

        # lib/hello_web/live/hello_live.ex
        defmodule HelloLive do
          use Phoenix.LiveView

          if Mix.env() == :dev do
            on_mount {#{inspect(__MODULE__)}, __MODULE__}
          end

        end

  ### Older Versions

  Note for LiveView < 0.17, if you would like to use LiveDebug,
  you may do so by invoking the hook function manually from your
  [`mount/3`](`c:Phoenix.LiveView.mount/3`) callback. However,
  to ensure the debug code cannot be invoked outside of the dev
  environment, it is recommended to create a separate module:

      defmodule MyLiveDebug do
        @moduledoc "Allows LiveDebug in the dev environment"

        if Mix.env() == :dev do
          defdelegate on_mount(view, params, session, socket),
            to: #{inspect(__MODULE__)}
        else
          def on_mount(_, _, _, socket),
            do: {:cont, socket}
        end
      end

  Then, in your LiveView, invoke your

      def mount(params, session, socket) do
        {:cont, socket} = MyLiveDebug.on_mount(__MODULE__, params, session, socket)
        # your mount code
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
    |> attach_hooks()

    {:cont, socket}
  end

  if function_exported?(Phoenix.LiveView, :attach_hook, 4) do
    defp attach_hooks(socket) do
      socket
      |> attach_hook(Debug, :handle_info, &on_handle_info/2)
      |> attach_hook(Debug, :handle_params, &on_handle_params/3)
    end
  else
    defp attach_hooks(socket), do: socket
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
