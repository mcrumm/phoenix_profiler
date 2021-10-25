defmodule PhoenixWeb.LiveProfiler do
  @moduledoc """
  Interactive profiler for LiveView processes.

  LiveProfiler performs two roles:

  * As a Plug, LiveProfiler injects the debug token into the
    session of the stateless HTTP response. The session acts
    as a transport between the stateless request/response and
    the LiveView process. Once the client makes the stateful
    connection, the debug token is picked up by the LiveView
    during the `mount` stage of the LiveView lifecycle.

  * When you use LiveProfiler, once the LiveView is connected,
    the profiler will join the LiveView process to the debug
    session for a given token. Once joined, the LiveView
    becomes a "process under profile". These processes can be
    monitored from the Phoenix Web Debug Toolbar in order to
    triage issues and tune performance.

  ## As a Plug

  As a Plug, LiveProfiler lives on the bottom of the `:browser` pipeline
  on your Router module, typically found in `lib/my_app_web/router.ex`:

      pipeline :browser do
        # plugs...
        plug PhoenixWeb.LiveProfiler
      end

  ## As a lifecycle hook

  As a LiveView lifecycle hook, LiveProfiler lives on a
  module where you use LiveView:

      defmodule PageLive do
        # use...
        use PhoenixWeb.LiveProfiler

        # callbacks...
      end

  In order to support as many versions Phoenix LiveView as possible,
  including versions before lifecycle hooks were introduced, the mount
  hook will be installed automatically when you `use PhoenixWeb.LiveProfiler`.

  See the LiveView Profiling section of the [`Profiler`](`PhoenixWeb.Profiler`) module docs.

  """
  import Phoenix.LiveView
  alias PhoenixWeb.Profiler.{Dumped, PubSub, Request, Session, Server}

  defmacro __using__(_) do
    quoted_mount_profiler = quoted_mount_profiler()

    quote do
      unquote(quoted_mount_profiler)

      def handle_cast({PhoenixWeb.LiveProfiler, _, _} = msg, socket) do
        PhoenixWeb.LiveProfiler.__handle_cast__(__MODULE__, msg, socket)
      end

      def handle_call({PhoenixWeb.LiveProfiler, _} = msg, _, socket) do
        PhoenixWeb.LiveProfiler.__handle_call__(__MODULE__, msg, socket)
      end
    end
  end

  @live_view_version ">= 0.17.0-dev"
  defp quoted_mount_profiler do
    if Code.ensure_loaded?(Phoenix.LiveView) and macro_exported?(Phoenix.LiveView, :on_mount, 1) do
      if Version.match?(to_string(Application.spec(:phoenix_live_view, :vsn)), @live_view_version) do
        quote do
          on_mount {PhoenixWeb.LiveProfiler, __MODULE__}

          @doc false
          def mount_profiler(socket, _params, _session) do
            PhoenixWeb.LiveProfiler.warn_mount_profiler(__MODULE__, socket)
          end
        end
      else
        # LiveView 0.16.x has a forward-incompatible on_mount API
        quote do
          on_mount {__MODULE__, :__on_mount_profiler__}

          def __on_mount_profiler__(params, session, socket) do
            PhoenixWeb.LiveProfiler.on_mount(__MODULE__, params, session, socket)
          end

          @doc false
          def mount_profiler(socket, _params, _session) do
            PhoenixWeb.LiveProfiler.warn_mount_profiler(__MODULE__, socket)
          end
        end
      end
    else
      # LiveView 0.14.x-0.15.x are supported during an initial on-ramp
      # period for users lagging updates. Those versions will likely
      # fall out of support very quickly, but making an inital release
      # available to more versions will help early adoption.
      quote do
        alias PhoenixWeb.LiveProfiler

        def mount_profiler(%Phoenix.LiveView.Socket{} = socket, params, session) do
          PhoenixWeb.LiveProfiler.mount_profiler(socket, params, session, __MODULE__)
        end
      end
    end
  end

  @behaviour Plug

  @private_key Request.session_key()
  @session_key Session.session_key()
  @token_key Request.token_key()

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _) do
    endpoint = conn.private.phoenix_endpoint
    config = endpoint.config(:phoenix_web_profiler)

    if config do
      token = Plug.Conn.get_session(conn, @session_key)
      conn = find_or_start_session(conn, token)

      Plug.Conn.put_session(conn, @token_key, Request.debug_token!(conn))
    else
      conn
    end
  end

  defp find_or_start_session(conn, token) when is_binary(token) and token != "" do
    topic = Server.topic(token)
    :ok = Phoenix.PubSub.subscribe(PubSub, topic)
    ref = make_ref()
    Phoenix.PubSub.broadcast_from(PubSub, self(), topic, {__MODULE__, :ping, {self(), ref}})

    receive do
      {Server, ^ref, _pid} ->
        Plug.Conn.put_private(conn, @private_key, token)
    after
      50 ->
        Session.listen(conn)
    end
  end

  defp find_or_start_session(conn, _token) do
    Session.listen(conn)
  end

  @doc false
  def mount_profiler(socket, params, session, module) do
    {:cont, socket} = PhoenixWeb.LiveProfiler.on_mount(module, params, session, socket)
    socket
  end

  @doc false
  def warn_mount_profiler(socket, module) do
    IO.warn("""
    PhoenixWeb.LiveProfiler was mounted automatically. Please remove the
    call to #{inspect(module)}.mount_profile/3 as it has no effect:

      mount_profile(socket, params, session)

    """)

    socket
  end

  def __handle_cast__(_module, {PhoenixWeb.LiveProfiler, {:dump, ref}, to: pid}, socket) do
    GenServer.cast(pid, {:dumped, ref, Dumped.flush()})
    {:noreply, socket}
  end

  def __handle_call__(_module, {PhoenixWeb.LiveProfiler, :assigns}, socket) do
    assigns =
      Phoenix.LiveView.Helpers.assigns_to_attributes(socket.assigns, [:live_action, :flash])

    {:reply, assigns, socket}
  end

  @doc false
  def on_mount(view_module, params, %{@session_key => _} = session, socket) do
    socket
    |> attach_hook(:phxweb_profiler_dump_assigns, :handle_info, &__handle__info__/2)
    |> apply_profiler_hooks(connected?(socket), view_module, params, session)
  end

  def on_mount(_view_module, _params, _session, socket) do
    {:cont, socket}
  end

  defp apply_profiler_hooks(socket, _connected? = false, _view_module, _params, _session) do
    {:cont, socket}
  end

  defp apply_profiler_hooks(socket, _connected? = true, view_module, _params, session) do
    Session.track(socket, session, %{
      kind: :profile,
      phoenix_live_action: socket.assigns.live_action,
      root_view: socket.private[:root_view],
      transport_pid: transport_pid(socket),
      view_module: view_module
    })

    {:cont, socket}
  end

  defp __handle__info__({:phxweb_profiler, {:dump_assigns, ref}, to: lv_pid}, socket) do
    assigns =
      Phoenix.LiveView.Helpers.assigns_to_attributes(socket.assigns, [:live_action, :flash])

    GenServer.cast(lv_pid, {:dumped_assigns, ref, assigns})
    {:halt, socket}
  end

  defp __handle__info__(_, socket) do
    {:cont, socket}
  end
end
