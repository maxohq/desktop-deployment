defmodule DesktopDeployment.Os.Macos.CopyFiles do
  use DesktopDeployment.Operation
  alias DesktopDeployment.Tooling
  alias DesktopDeployment.Package

  def call(opts \\ []) do
    Operation.new()
    |> run(:handle_macos, fn -> handle_macos(opts) end)
    |> respond()
  end

  defp respond(result) do
    Operation.log_error(result, "Error in Macos.CopyFiles")

    case result do
      {:ok, ctx} -> {:ok, ctx.handle_macos}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end

  defp handle_macos(%Package{release: %Mix.Release{} = rel} = pkg) do
    # Importing dependend libraries

    libs = Tooling.wildcard(rel, "**/*.dylib") ++ Tooling.wildcard(rel, "**/*.so")
    log("Found libs: #{inspect(libs)}")
    for lib <- libs, do: Tooling.strip_symbols(lib)

    log("Finding All Deps")
    deps = Tooling.find_all_deps(Macos, libs)

    log("Importing All Deps")
    for lib <- deps, do: Tooling.priv_import!(pkg, lib)

    pkg |> Result.ok()
  end
end
