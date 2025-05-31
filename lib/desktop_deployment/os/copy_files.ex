defmodule DesktopDeployment.Os.CopyFiles do
  use DesktopDeployment.Operation
  alias DesktopDeployment.Package
  alias DesktopDeployment.Tooling

  def call(package) do
    Operation.new()
    |> run(:common_files, fn -> copy_common_files(package) end)
    |> run(:unix_files, fn ->
      copy_unix_files(package, Tooling.os() in [Macos, Linux])
    end)
    |> run(:os_specific_files, fn ctx ->
      copy_os_specific_files(Tooling.os(), ctx.unix_files)
    end)
    |> respond()
  end

  def respond(result) do
    if elem(result, 0) == :error do
      IO.inspect(result, label: "*** CopyFiles ERROR ***")
    end

    case result do
      {:ok, ctx} -> {:ok, ctx.common_files}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end

  defp copy_common_files(
         %Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg
       ) do
    vm_args = Tooling.toolpath("rel/vm.args.eex")
    content = Tooling.eval_eex(vm_args, rel, pkg)
    vm_args_out = Path.join([rel_path, "releases", vsn, "vm.args"])
    File.write!(vm_args_out, content)

    Result.ok(pkg)
  end

  defp copy_unix_files(pkg, false) do
    Result.ok(pkg)
  end

  defp copy_unix_files(%Package{release: %Mix.Release{} = rel} = pkg, true) do
    [beam] = Tooling.wildcard(rel, "**/beam.smp")
    # Chaning emulator name
    [erl] = Tooling.wildcard(rel, "**/bin/erl")
    Tooling.file_replace(erl, "EMU=beam", "EMU=#{pkg.name}")

    # Trying to remove .smp ending
    # unsafe binary editing (confirmed to work on 23.x)
    [erlexec] = Tooling.wildcard(rel, "**/bin/erlexec")
    Tooling.file_replace(erlexec, ".smp", <<0, 0, 0, 0>>)

    # Figuring out the result of our edits
    # and renaming beam
    System.put_env("EMU", pkg.name)
    name = Tooling.cmd!(erlexec, ["-emu_name_exit"])
    pkg = %{pkg | priv: Map.put(pkg.priv, :executable_name, name)}

    # Unsafe binary removal of "Erlang", needs same length!
    Tooling.file_replace(beam, "Erlang", binary_part(pkg.name <> <<0, 0, 0, 0, 0, 0>>, 0, 6))
    Tooling.strip_symbols(beam)
    File.rename!(beam, Path.join(Path.dirname(beam), name))

    ## return changed package
    Result.ok(pkg)
  end

  defp copy_os_specific_files(os, opts) do
    case os do
      Linux -> DesktopDeployment.Os.Linux.CopyFiles.call(opts)
      Windows -> DesktopDeployment.Os.Windows.CopyFiles.call(opts)
      Macos -> DesktopDeployment.Os.Macos.CopyFiles.call(opts)
    end
  end
end
