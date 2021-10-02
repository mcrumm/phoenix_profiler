# FriendsOfPhoenix.Debug

<!-- MDOC !-->
The Debug Toolbar for Phoenix HTML requests.

The toolbar seeks to provide the following:

* Response data (status code, headers?, session [y|n], etc.)
* Route/Path - controller/action/view, live_view/live_action, etc.
* Basic diagnostics - response time, heap size?
* Mailer preview
* Debug assigns
* Debug LiveView crashes

Importantly, the debug package is not:

* Replacing LiveDashboard
* Suitable for running in production

## Installation

> Note you must complete the [Phoenix LiveView installation](https://hexdocs.pm/phoenix_live_view/installation.html) before
> installing the Debug package.

Add fophx_debug to your `mix.exs`:

```elixir
{:fophx_debug, "~> 0.1.0", runtime: Mix.env() == :dev}
```

## Usage

Add the plug at the bottom of the `if code_reloading? do` block
on your Endpoint, typically found at `lib/my_app_web/endpoint.ex`:

```elixir
if code_reloading? do
  # ...plugs...
  plug FriendsOfPhoenix.Debug, session: @session_options
end
```

## Configuration

All configuration is done on the Plug. The following options are available:

* `:session` - Required. The value must be the same as the
  options given to `Plug.Session`. When given a tuple
  `{Module, :function, [arg1, arg2, ...]}`, it will be invoked
  at runtime and must return valid session options.

* `:live_socket_path` - The path to the LiveView socket.
  Defaults to `"/live"`.

* `:iframe_attrs` - HTML attributes to be given to the iframe
  injected for the toolbar. Expects a keyword list of atom keys and
  string values. Defaults to `[]`.

## LiveView Profiling

To enable LiveView debugging, add the LiveProfiler plug to the
`:browser` pipeline on your Router, typically found in
`lib/my_app_web/router.ex`:

```elixir
pipeline :browser do
  # ...plugs...
  if Mix.env() == :dev do
    plug FriendsOfPhoenix.LiveProfiler
  end
end
```

...and mount LiveProfiler on the `:live_view` function in your web module,
typically found at `lib/my_app_web.ex`:

```elixir
# Add this after: use Phoenix.LiveView, ...
if Mix.env() == :dev do
  on_mount {FriendsOfPhoenix.LiveProfiler, __MODULE__}
end
```

See the [`LiveProfiler`](`FriendsOfPhoenix.LiveProfiler`) module docs for more mount options.

<!-- MDOC !-->

## License

MIT License. Copyright (c) 2021 Michael Allen Crumm Jr.
