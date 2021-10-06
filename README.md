# PhoenixWeb.Profiler

<!-- MDOC !-->
Provides a **development tool** that gives detailed information about the execution of any request.

## Built-in Features

* HTTP Response metadata - status code, endpoint, router, controller/action, live_view/live_action, etc.

* Basic diagnostics - response time, heap size (todo)

* Inspect LiveView crashes

* Profiler assigns (TODO)

* Mailer preview shortcut (TODO)

## Installation

To start using the profiler, you will need three steps:

1. Add the `phoenix_web_profiler` dependency
2. Configure LiveView
3. Add the PhoenixWeb.Profiler Plug

### 1. Add the phoenix_web_profiler dependency

Add phoenix_web_profiler to your `mix.exs`:

```elixir
{:phoenix_web_profiler, "~> 0.1.0", runtime: Mix.env() == :dev}
```

### 2. Configure LiveView

> If LiveView is already installed in your app, you may skip this section.

The Phoenix Web Debug Toolbar is built on top of LiveView. If you plan to use LiveView in your application in the future, or if you wish to use the LiveProfiler, we recommend you follow [the official installation instructions](https://hexdocs.pm/phoenix_live_view/installation.html).
This guide only covers the minimum steps necessary for the Profiler itself to run.

Update your endpoint's configuration to include a signing salt. You can generate a signing salt by running `mix phx.gen.secret 32` (note Phoenix v1.5+ apps already have this configuration):

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  live_view: [signing_salt: "SECRET_SALT"]
```

### 3. Add the PhoenixWeb.Profiler Plug

Add the plug at the bottom of the `if code_reloading? do` block
on your Endpoint, typically found at `lib/my_app_web/endpoint.ex`:

```elixir
if code_reloading? do
  # plugs...
  plug PhoenixWeb.Profiler
end
```

All configuration is done on the Plug. The following options are available:

* `:live_socket_path` - The path to the LiveView socket.
  Defaults to `"/live"`.

* `:toolbar_attrs` - HTML attributes to be given to the element
  injected for the toolbar. Expects a keyword list of atom keys and
  string values. Defaults to `[]`.

This is all. Run `mix phx.server` and view the toolbar in your browser requests.

Optionally you may wish to continue on to [LiveView Profiling](#module-liveview-profiling).

## LiveView Profiling

To enable LiveView profiling, you will need two more steps:

1. Add the PhoenixWeb.LiveProfiler plug
2. Add the PhoenixWeb.LiveProfiler lifecycle hook

### 1. Add the PhoenixWeb.LiveProfiler plug

Add the LiveProfiler plug to the bottom of the
`:browser` pipeline on your Router, typically found in
`lib/my_app_web/router.ex`:

```elixir
pipeline :browser do
  # plugs...
  if Mix.env() == :dev do
    plug PhoenixWeb.LiveProfiler
  end
end
```

### 2. Add the PhoenixWeb.LiveProfiler hook

> Note this requires LiveView 0.17+.
> For older versions, see [Profiling LiveView prior to 0.17](#module-profiling-liveview-prior-to-0-17).

Add the LiveProfiler hook within the `live_view` function on your
web module, typically found at `lib/my_app_web.ex`.

For example, if your `live_view` function looks like this:

```elixir
  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {HelloWeb.LayoutView, "live.html"}

      unquote(view_helpers())
    end
  end
```

Change the function to:

```elixir
def live_view do
  quote do
    use Phoenix.LiveView,
      layout: {HelloWeb.LayoutView, "live.html"}

    if Mix.env() == :dev do
      on_mount {PhoenixWeb.LiveProfiler, __MODULE__}
    end

    unquote(view_helpers())
  end
end
```

Now you are debugging with LiveView. Happy gardening!

### Profiling LiveView prior to 0.17

Note for LiveView < 0.17, if you would like to use LiveProfiler,
you may do so by invoking the hook function manually from your
[`mount/3`](`c:Phoenix.LiveView.mount/3`) callback. However,
to ensure the profiler cannot accidentally be invoked outside
of the dev environment, it is recommended to create a separate
module:

```elixir
defmodule MyLiveProfiler do
  @moduledoc "Allows LiveProfiler only in the dev environment"

  if Mix.env() == :dev do
    defdelegate on_mount(view, params, session, socket),
      to: PhoenixWeb.LiveProfiler
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

  # mount...

  {:ok, socket}
end
```

<!-- MDOC !-->

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
