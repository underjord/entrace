defmodule Entrace.Router do
  @moduledoc """
  Provides LiveView routing for Entrace.
  """

  @doc """
  Defines an Entrace route.

  It expects the `path` the tracing tool will be mounted at
  and a set of options.

  ## Examples

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Entrace.Router

        scope "/", MyAppWeb do
          pipe_through [:browser]
          entrace "/tracing"
        end
      end

  """
  defmacro entrace(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    scope =
      quote bind_quoted: binding() do
        scope path, alias: false, as: false do
          {session_name, session_opts, route_opts} = Entrace.Router.__options__(opts)

          import Phoenix.Router, only: [get: 4]
          import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

          live_session session_name, session_opts do
            # Assets
            get "/css-:md5", Entrace.Assets, :css, as: :entrace_asset
            get "/js-:md5", Entrace.Assets, :js, as: :entrace_asset

            # All helpers are public contracts and cannot be changed
            live "/", Entrace.PageLive, :home, route_opts
            live "/:page", Entrace.PageLive, :page, route_opts
          end
        end
      end

    quote do
      unquote(scope)

      unless Module.get_attribute(__MODULE__, :entrace_prefix) do
        @entrace_prefix Phoenix.Router.scoped_path(__MODULE__, path)
        def __entrace_prefix__, do: @entrace_prefix
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:entrace, 2}})

  defp expand_alias(other, _env), do: other

  @doc false
  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")

    session_args = []

    {
      options[:live_session_name] || :entrace,
      [
        session: {__MODULE__, :__session__, session_args},
        root_layout: {Entrace.LayoutView, :dash},
        on_mount: options[:on_mount] || nil
      ],
      [
        private: %{live_socket_path: live_socket_path},
        as: :entrace
      ]
    }
  end

  @doc false
  def __session__(conn) do
    %{}
  end
end
