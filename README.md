# PhoenixProfiler

<!-- MDOC -->
Provides a **development tool** that gives detailed information about the execution of any request.

**Never** enable it on production servers as it exposes sensitive data about your web application.

## Built-in Features

* Request/Response - status code, params, headers, cookies, etc.

* Routing - endpoint, router, controller/live view, action, etc.

* Basic diagnostics - response time, memory

* Inspect LiveView crashes

* Inspect Ecto queries (Coming Soon)

* Swoosh mailer integration (Coming Soon)

## Installation

To start using the profiler, you will need the following steps:

1. Add the `phoenix_profiler` dependency
2. Define a profiler on your supervision tree
3. Enable the profiler on your Endpoint
4. Configure LiveView
5. Add the `PhoenixProfiler` plug
6. Mount the profiler on your LiveViews
7. Add the profiler page on your LiveDashboard (optional)

### 1. Add the phoenix_profiler dependency

Add phoenix_profiler to your `mix.exs`:

```elixir
{:phoenix_profiler, "~> 0.1.0", github: "mcrumm/phoenix_profiler"}
```

### 2. Define a profiler on your supervision tree

You define a profiler on your main application's supervision
tree (usually in `lib/my_app/application.ex`):

```elixir
    children = [
      {PhoenixProfiler, name: MyAppWeb.Profiler},
      # MyApp.Repo
      # MyAppWeb.Endpoint,
      # etc...
    ]
```

Note that the profiler must be running for data to be collected,
so it must come before any endpoints in your supervision tree.

The following options are available:

* `:name` - The name of the profiler server. This option is required.

* `:request_sweep_interval` - How often to sweep the ETS table where
  the profiles are stored. Default is `24h` in milliseconds.

### 3. Enable the profiler on your Endpoint

PhoenixProfiler is disabled by default. In order to enable it,
you must update your endpoint's `:dev` configuration to include the
`:phoenix_profiler` options:

```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  phoenix_profiler: [server: MyAppWeb.Profiler]
```

All web configuration is done inside the `:phoenix_profiler` key on the endpoint.

The following options are available:

* `:server` - The name of the profiler server. This option is required.

* `:enable` - When set to `false`, disables profiling by default. You can
  always enable profiling on a request via `enable/1`. Defaults to `true`.

* `:profiler_link_base` - The base path for generating links
  on the toolbar. Defaults to `"/dashboard/_profiler"`.

* `:toolbar_attrs` - HTML attributes to be given to the element
  injected for the toolbar. Expects a keyword list of atom keys and
  string values. Defaults to `[]`.

### 4. Configure LiveView

> If LiveView is already installed in your app, you may skip this section.

The Phoenix Web Debug Toolbar is built on top of LiveView. If you plan to use LiveView in your application in the future we recommend you follow [the official installation instructions](https://hexdocs.pm/phoenix_live_view/installation.html).
This guide only covers the minimum steps necessary for the toolbar itself to run.

Update your endpoint's configuration to include a signing salt. You can generate a signing salt by running `mix phx.gen.secret 32` (note Phoenix v1.5+ apps already have this configuration):

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  live_view: [signing_salt: "SECRET_SALT"]
```

### 5. Add the PhoenixProfiler plug

Add the `PhoenixProfiler` plug within the `code_reloading?`
block on your Endpoint (usually in `lib/my_app_web/endpoint.ex`):

```elixir
  if code_reloading? do
    # plugs...
    plug PhoenixProfiler
  end
```

### 6. Mount the profiler on your LiveViews

Note this section is required only if you are using LiveView, otherwise you may skip it.

Add the profiler hook to the `live_view` function on your
web module (usually in `lib/my_app_web.ex`):

```elixir
  def live_view do
    quote do
      # use...

      on_mount PhoenixProfiler

      # view helpers...
    end
  end
```

Note the [`on_mount`](`Phoenix.LiveView.on_mount/1`) macro requires LiveView 0.16+. For earlier versions,
see `PhoenixProfiler.enable/1`.

This is all. Run `mix phx.server` and observe the toolbar on your browser requests.

### 7. Add the profiler page on your LiveDashboard (optional)

Note this section is required for the LiveDashboard integration. If you are
not using LiveDashboard, you may technically skip this step, although it is
highly recommended that you
[install LiveDashboard](https://hexdocs.pm/phoenix_live_dashboard/Phoenix.LiveDashboard.html#module-installation)
to enjoy all the features of PhoenixProfiler.

Add the dashboard definition to the list of `:additional_pages` on
the [`live_dashboard`](`Phoenix.LiveDashboard.Router.live_dashboard/2`) macro
in your router (usually in `lib/my_app_web/router.ex`):

```elixir
live_dashboard "/dashboard",
  additional_pages: [
    _profiler: {PhoenixProfiler.Dashboard, []}
    # additional pages...
  ]
```

## Reduced motion toolbar options

If a `PHOENIX_PROFILER_REDUCED_MOTION` environment variable is set,
`PhoenixProfiler` will disable all toolbar animations. The value of the
environment variable is not evaluated.

<!-- MDOC -->

## Contributing

For those planning to contribute to this project, you can run a dev app with the following commands:

    $ mix setup
    $ mix dev

Alternatively, run `iex -S mix dev` if you also want a shell.

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
