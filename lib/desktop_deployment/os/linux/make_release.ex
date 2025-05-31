defmodule DesktopDeployment.Os.Linux.MakeRelease do
  use DesktopDeployment.Operation

  def call(pkg) do
    Operation.new()
    |> Operation.run(:first, fn -> first_action(pkg) end)
    |> IO.inspect()
    |> respond()
  end

  defp respond(result) do
    Operation.log_error(result, "Error in Linux.MakeRelease")

    case result do
      {:ok, ctx} -> {:ok, ctx.first}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end

  defp first_action(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    arch = Tooling.arch()
    out_file = Path.join(build_root, "#{pkg.name}-#{vsn}-linux-#{arch}.run")

    File.rm(out_file)

    content = Tooling.eval_eex(Tooling.toolpath("rel/linux/install.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "install"), content)
    File.chmod!(Path.join(rel_path, "install"), 0o755)

    run_content = Tooling.eval_eex(Tooling.toolpath("rel/linux/run.eex"), rel, pkg)
    File.write!(Path.join(rel_path, pkg.name), run_content)
    File.chmod!(Path.join(rel_path, pkg.name), 0o755)

    # Remove the original release bin/ dir
    File.rm_rf!(Path.join(rel_path, "bin"))

    :file.set_cwd(String.to_charlist(rel_path))

    Tooling.cmd!(Tooling.toolpath("rel/linux/makeself.sh"), [
      "--xz",
      "--threads",
      "0",
      rel_path,
      out_file,
      pkg.name,
      "./install"
    ])

    %{pkg | priv: Map.put(pkg.priv, :installer_name, out_file)} |> Result.ok()
  end
end
