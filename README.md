# PhoenixProfiler

<!-- MDOC -->
Provides a **development tool** that gives detailed information about the execution of any request.

**Never** enable it on production servers as it exposes sensitive data about your web application.

## Built-in Features

* HTTP Response metadata - status code, endpoint, router, controller/action, live_view/live_action, etc.

* Basic diagnostics - response time, memory

* Inspect LiveView crashes

* Mailer preview shortcut (TODO)

## Installation

To start using the profiler, you will need the following steps:

1. Add the `phoenix_web_profiler` dependency
2. Enable the profiler on your Endpoint
3. Configure LiveView
4. Add the `PhoenixProfiler` Plug
5. Mount the profiler on your LiveViews
6. Configure the toolbar (optional)

### 1. Add the phoenix_web_profiler dependency

Add phoenix_web_profiler to your `mix.exs`:

```elixir
{:phoenix_web_profiler, "~> 0.1.0", git: "git@github.com:mcrumm/phoenix_web_profiler.git"}
```

### 2. Enable the profiler on your Endpoint

The Phoenix Web Profiler is disabled by default. In order to enable it,
update your endpoint's `:dev` configuration to include the
`:phoenix_web_profiler` key:

```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  phoenix_web_profiler: true
```

### 3. Configure LiveView

> If LiveView is already installed in your app, you may skip this section.

The Phoenix Web Debug Toolbar is built on top of LiveView. If you plan to use LiveView in your application in the future, or if you wish to use the LiveProfiler, we recommend you follow [the official installation instructions](https://hexdocs.pm/phoenix_live_view/installation.html).
This guide only covers the minimum steps necessary for the Profiler itself to run.

Update your endpoint's configuration to include a signing salt. You can generate a signing salt by running `mix phx.gen.secret 32` (note Phoenix v1.5+ apps already have this configuration):

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  live_view: [signing_salt: "SECRET_SALT"]
```

### 4. Add the profiler Plug

Add the `PhoenixProfiler` plug on the bottom of the
`if code_reloading? do` block on your Endpoint,
typically found at `lib/my_app_web/endpoint.ex`:

```elixir
# endpoint.ex
if code_reloading? do
  # plugs...
  plug PhoenixProfiler
end
```

Additional configuration is done on the Plug. The following options are available:

* `:toolbar_attrs` - HTML attributes to be given to the element
  injected for the toolbar. Expects a keyword list of atom keys and
  string values. Defaults to `[]`.

### 5. Mount the profiler on your LiveViews

Note this section is required only if you are using LiveView, otherwise you may skip it.

Add the profiler hook to the `live_view` function on your
web module, typically found at `lib/my_app_web.ex`:

```elixir
  def live_view do
    quote do
      # use...
      on_mount PhoenixProfiler

      # view helpers...
    end
  end
```

Note the `on_mount` macro requires LiveView 0.16+. For earlier versions,
see `PhoenixProfiler.enable_live_profiler/1`.

This is all. Run `mix phx.server` and observe the toolbar on your browser requests.

### 6. Configure the toolbar (optional)

It's also possible to configure the toolbar by exporting ENV vars as you wish:

* `PHOENIX_WEB_PROFILER_REDUCED_MOTION` - To disable the show/hide animation.
  Expects to be defined with any value. Defaults to empty (unset).

<!-- MDOC -->

## Contributing

For those planning to contribute to this project, you can run a dev app with the following commands:

    $ mix setup
    $ mix dev

Alternatively, run `iex -S mix dev` if you also want a shell.

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
