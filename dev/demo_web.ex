defmodule DemoWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: DemoWeb

      import Plug.Conn
      import PhoenixWeb.Profiler, only: [dump: 1]
      alias DemoWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "dev/demo_web/templates",
        namespace: DemoWeb

      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      unquote(view_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {DemoWeb.LayoutView, "live.html"}

      use PhoenixWeb.LiveProfiler

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.LiveView.Helpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      # Import dev debug functionality (dump)
      import PhoenixWeb.Profiler, only: [dump: 1]

      alias DemoWeb.Router.Helpers, as: Routes
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
