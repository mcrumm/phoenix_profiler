defmodule FriendsOfPhoenix.LiveProfiler do
  @moduledoc """
  Interactive profiler for LiveView processes.

  ## Configuration

  First, add LiveProfiler as a plug in your `:browser` pipeline:

  ```elixir
  pipeline :browser do
    # ...plugs...
    if Mix.env() == :dev do
      plug FriendsOfPhoenix.LiveProfiler
    end
  end
  ```

  Next, add the following block to a LiveView:

  ```elixir
  if Mix.env() == :dev do
    on_mount {#{inspect(__MODULE__)}, __MODULE__}
  end
  ```

  Usually you will add the block to the `:live_view` function in your web
  module, typically found at `lib/my_app_web.ex`:

  ```elixir
  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {HelloWeb.LayoutView, "live.html"}

      # ... add the block here ...

      unquote(view_helpers())
    end
  end
  ```

  Alternately, you can put it directly on a LiveView module:

  ```elixir
  defmodule HelloLive do
    use Phoenix.LiveView

    # ...add the block here...

  end
  ```

  ### Older Versions

  Note for LiveView < 0.17, if you would like to use LiveProfiler,
  you may do so by invoking the hook function manually from your
  [`mount/3`](`c:Phoenix.LiveView.mount/3`) callback. However,
  to ensure the debug code cannot be invoked outside of the dev
  environment, it is recommended to create a separate module:

  ```elixir
  defmodule MyLiveProfiler do
    @moduledoc "Allows LiveProfiler in the dev environment"

    if Mix.env() == :dev do
      defdelegate on_mount(view, params, session, socket),
        to: #{inspect(__MODULE__)}
    else
      def on_mount(_, _, _, socket),
        do: {:cont, socket}
    end
  end
  ```

  Then, in your LiveView, invoke your on_mount function:

  ```elixir
  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    {:cont, socket} = MyLiveProfiler.on_mount(__MODULE__, params, session, socket)

    # ...mount...

    {:ok, socket}
  end
  ```

  """
  import Phoenix.LiveView
  alias FriendsOfPhoenix.Debug

  @behaviour Plug

  @private_key :fophx_debug
  @session_key "fophx_debug"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{private: %{@private_key => token}} = conn, _) do
    Plug.Conn.put_session(conn, @session_key, token)
  end

  def call(conn, _), do: conn

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
    Debug.track(socket, token, %{
      kind: :profile,
      phoenix_live_action: socket.assigns.live_action,
      root_view: socket.private[:root_view],
      transport_pid: transport_pid(socket),
      view_pid: self(),
      view_module: view_module
    })

    {:cont, socket}
  end
end
