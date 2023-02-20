# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes

The `PhoenixProfiler` server is now started by the application. Remove the child spec from your telemetry supervisor:

```diff
# lib/my_app_web/telemetry.ex
children = [
-      {PhoenixProfiler, name: MyAppWeb.Profiler},
      # :telemetry_poller, etc.
]
```

... and remove the `:server` option from the `:phoenix_profiler` options on your Endpoint config:

```diff
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
-  phoenix_profiler: [server: MyAppWeb.Profiler]
+  phoenix_profiler: []
```

### Changed

- `PhoenixProfiler.reset/1` is now `PhoenixProfiler.reset/0`.

### Removed

- `PhoenixProfiler.all_running/0`
- `PhoenixProfiler.child_spec/1`
- The `:server` option from the Endpoint config.

## [0.2.1] - 2023-01-26

- Remove implicit dependency on phoenix_view

## [0.2.0] - 2022-09-28

### Added

- Support for LiveView 0.18.0  (#65)
- Handle multiple body tags (#60)

### Removed

- Support for LiveView < 0.16.0 (#65)

## [0.1.0] - 2022-03-03
### Added

- Initial release of the web profiler and debug toolbar.


[Unreleased]: https://github.com/mcrumm/phoenix_profiler/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/mcrumm/phoenix_profiler/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mcrumm/phoenix_profiler/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mcrumm/phoenix_profiler/releases/tag/v0.1.0
