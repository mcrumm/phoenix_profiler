# PhoenixWeb.Profiler

<!-- MDOC !-->
Provides a **development tool** that gives detailed information about the execution of any request.

**Never** enable it on production servers as it exposes sensitive data about your web application.

## Built-in Features

* HTTP Response metadata - status code, endpoint, router, controller/action, live_view/live_action, etc.

* Basic diagnostics - response time, memory

* Inspect LiveView crashes

* Dump assigns to the profiler

* Mailer preview shortcut (TODO)

## Installation

To start using the profiler, you will need the following steps:

1. Add the `phoenix_web_profiler` dependency
2. Configure LiveView
3. Add the `PhoenixWeb.Profiler` Plug
4. Add the `PhoenixWeb.LiveProfiler` Plug
5. `use PhoenixWeb.LiveProfiler` on your LiveViews
6. Import the `dump/1` macro

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

Add the Profiler plug on the bottom of the `if code_reloading? do` block
on your Endpoint, typically found at `lib/my_app_web/endpoint.ex`:

```elixir
# endpoint.ex
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

### 4. Add the PhoenixWeb.LiveProfiler Plug

Add the LiveProfiler plug on the bottom of the
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

### 5. Use PhoenixWeb.LiveProfiler on your LiveViews

Note this section is required only if you are using LiveView, otherwise you may skip it.

Add the LiveProfiler hook to the `live_view` function on your
web module, typically found at `lib/my_app_web.ex`:

```elixir
  def live_view do
    quote do
      # use...

      if Mix.env() == :dev do
        use Phoenix.LiveProfiler
      end

      # view helpers...
    end
  end
```

### Add the dump/1 macro

Add the `dump/1` macro to the `view_helpers` function on
your web module, typically found at: `lib/my_app_web.ex`:

```elixir
# lib/my_app_web.ex
def view_helpers do
  quote do
    # use...
    # import...

    # Import dev debug functionality (dump)
    import PhoenixWeb.Profiler, only: [dump: 1]

    # import...
    # alias...
  end
end
```

If you wish to debug from Phoenix Controllers, do not forget to
import dump to the `controller` function on the same module:

```elixir
# lib/my_app_web.ex
def controller do
 quote do
    # use...
    # import...
    import PhoenixWeb.Profiler, only: [dump: 1]
    # alias...
  end
end
```

This is all. Run `mix phx.server` and observe the toolbar on your browser requests.

## LiveView 0.14.x-0.15.x

Note for LiveView 0.14.x-0.15.x, if you would like to use LiveProfiler
to the extent that it is supported, you must mount the profiler manually
from within your [`mount/3`](`c:Phoenix.LiveView.mount/3`) callback.

When you use LiveProfiler, it will inject a `mount_profiler/1` function
into your LiveViews You must invoke it in your `mount/3` function to
enable profiling:

```elixir
defmodule HelloLive do
  use Phoenix.LiveView
  use PhoenixWeb.LiveProfiler

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    {:ok, mount_profiler(socket)}
  end
end
```

Note this is a convenience because we would like to see the largest
possible adoption of the debug toolbar. Backwards-compatibility will
not be maintained forever, and many features many not be available on
older LiveView versions, so for the best possible operation,
please stay up-to-date with LiveView releases.

When you update your LiveView dependency, `mount_profiler/1` will begin to
emit a warning recommending its own removal.

<!-- MDOC !-->

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
