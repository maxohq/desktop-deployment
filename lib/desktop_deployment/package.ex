defmodule DesktopDeployment.Package do
  defstruct name: "ElixirApp",
            name_long: "The Elixir App",
            company: "Elixir",
            description: "An Elixir App for Dekstop",
            description_long: "An Elixir App for Desktop powered by Phoenix LiveView",
            icon: "priv/icon.png",
            # https://developer.gnome.org/menu-spec/#additional-category-registry
            category_gnome: "GNOME;GTK;Office;",
            category_macos: "public.app-category.productivity",
            identifier: "io.elixirdesktop.app",
            # additional ELIXIR_ERL_OPTIONS for boot
            elixir_erl_options: "",
            # additional ENV variables for boot
            env: %{},
            # import options
            import_inofitywait: false,
            # defined during the process
            app_name: nil,
            release: nil,
            priv: %{},
            schemes: []
end
