# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* Ensure dashboard profiles list respects the selected limit

### Changed

#### `use PhoenixProfiler` on your Endpoint

PhoenixProfiler needs to wrap the whole Plug pipeline to get
a complete picture of each request. Make the following changes
in your Endpoint module(s):

1. Add `use PhoenixProfiler` directly after `use Phoenix.Endpoint`:

```diff
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
+ use PhoenixProfiler
```

2. Remove the plug from the `code_reloading?` block:

```diff
if code_reloading? do
-  plug PhoenixProfiler
end
```


## [0.1.0] - 2022-03-03
### Added

- Initial release of the web profiler and debug toolbar.


[Unreleased]: https://github.com/mcrumm/phoenix_profiler/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mcrumm/phoenix_profiler/releases/tag/v0.1.0
