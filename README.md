# PhoenixWeb.Debug

<!-- MDOC !-->
Provides a **development tool** that gives detailed information about the execution of any request.

## Built-in Features

* HTTP Response metadata - status code, endpoint, router, controller/action, live_view/live_action, etc.

* Basic diagnostics - response time, heap size (todo)

* Inspect LiveView crashes

* Debug assigns (TODO)

* Mailer preview shortcut (TODO)

## Installation

Add phoenix_web_debug to your `mix.exs`:

```elixir
{:phoenix_web_debug, "~> 0.1.0", runtime: Mix.env() == :dev}
```

## Usage

Add the plug at the bottom of the `if code_reloading? do` block
on your Endpoint, typically found at `lib/my_app_web/endpoint.ex`:

```elixir
if code_reloading? do
  # plugs...
  plug PhoenixWeb.Debug
end
```

## Configuration

All configuration is done on the Plug. The following options are available:

* `:live_socket_path` - The path to the LiveView socket.
  Defaults to `"/live"`.

* `:toolbar_attrs` - HTML attributes to be given to the element
  injected for the toolbar. Expects a keyword list of atom keys and
  string values. Defaults to `[]`.

## LiveView Profiling

To enable LiveView debugging, add the LiveProfiler plug to the
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

...and mount LiveProfiler for LiveView the `live_view` function in your web module,
typically found at `lib/my_app_web.ex`.

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

See the [`LiveProfiler`](`PhoenixWeb.LiveProfiler`) module docs for more mount options.

<!-- MDOC !-->

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
