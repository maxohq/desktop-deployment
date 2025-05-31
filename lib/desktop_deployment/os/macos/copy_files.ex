defmodule DesktopDeployment.Os.Macos.CopyFiles do
  use DesktopDeployment.Operation
  alias DesktopDeployment.Tooling
  alias DesktopDeployment.Package

  def call(opts \\ []) do
    Operation.new()
    |> run(:fix_install_name_for_prod_deps, fn -> fix_install_name_for_prod_deps(opts) end)
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

  ## we need to fix the install name of the libs, because it can point to a non-existing path (since the native lib was pre-compiled on a different machine)
  ## for this we need to FIRST use the prod lib path (NOT RELEASE), fix the files there, and then we can continue.
  ## see issues/ci-path-on-osx-deps.txt for more details.
  defp fix_install_name_for_prod_deps(%Package{release: %Mix.Release{} = rel} = pkg) do
    prod_lib_path = get_prod_lib_path(rel)

    libs =
      Tooling.wildcard(prod_lib_path, "**/*.dylib") ++ Tooling.wildcard(prod_lib_path, "**/*.so")

    for lib <- libs, do: adjust_install_name(lib)

    pkg |> Result.ok()
  end

  defp get_prod_lib_path(%Mix.Release{} = rel) do
    # Get the release path and convert to lib path
    # Example: "/Users/user/Desktop/work/myapp/_build/prod/rel/default_release" ->  "/Users/user/Desktop/work/myapp/_build/prod/lib"

    rel.path
    |> Path.split()
    |> Enum.reverse()
    |> case do
      [_release_name, "rel" | rest] ->
        rest
        |> Enum.reverse()
        |> Kernel.++(["lib"])
        |> Path.join()

      _ ->
        # Fallback: replace "/rel/" with "/lib/" if the structure is unexpected
        String.replace(rel.path, ~r{/rel/[^/]+$}, "/lib")
    end
  end

  defp handle_macos(%Package{release: %Mix.Release{} = rel} = pkg) do
    # Importing dependend libraries

    log("RELEASE: #{inspect(rel)}")

    libs = Tooling.wildcard(rel, "**/*.dylib") ++ Tooling.wildcard(rel, "**/*.so")
    log("Found libs: #{inspect(libs)}")

    log("Stripping Symbols")
    for lib <- libs, do: Tooling.strip_symbols(lib)

    log("Finding All Deps")
    deps = Tooling.find_all_deps(Macos, libs)

    log("Importing All Deps")
    for lib <- deps, do: Tooling.priv_import!(pkg, lib)

    pkg |> Result.ok()
  end

  defp adjust_install_name(lib) do
    Tooling.cmd!("install_name_tool", ["-id", lib, lib])
  end
end
