defmodule DesktopDeployment.Os.Windows.CopyFiles do
  use DesktopDeployment.Operation
  alias DesktopDeployment.Package
  alias DesktopDeployment.Tooling

  def call(pkg) do
    Operation.new()
    |> run(:handle_windows, fn -> handle_windows(pkg) end)
    |> respond()
  end

  defp respond(result) do
    Operation.log_error(result, "Error in Windows.CopyFiles")

    case result do
      {:ok, ctx} -> {:ok, ctx.handle_windows}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end

  defp handle_windows(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    # Windows renaming exectuable
    [erl] = Tooling.wildcard(rel, "**/erl.exe")
    new_name = Path.join(Path.dirname(erl), pkg.name <> ".exe")
    File.rename!(erl, new_name)

    # Updating icon
    Tooling.cmd!("magick", ["convert", "-resize", "64x64", pkg.icon, "icon.ico"])

    Tooling.priv_import!(pkg, "icon.ico", strip: false)

    icon = Path.join(Tooling.priv(pkg), "icon.ico")
    content = Tooling.eval_eex(Tooling.toolpath("rel/win32/app.exe.manifest.eex"), rel, pkg)
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    File.write!(Path.join(build_root, "app.exe.manifest"), content)

    # fetch extra env file
    if File.exists?("rel/win32/app.env.eex") do
      content = Tooling.eval_eex("rel/win32/app.env.eex", rel, pkg)
      File.write!(new_name <> ".env", content)
    end

    git_version =
      with {version, 0} <- System.cmd("git", ["describe", "--tags", "--always"]) do
        String.trim(version)
      end

    info =
      %{
        "CompanyName" => pkg.company,
        "FileDescription" => pkg.description,
        "FileVersion" => git_version || vsn,
        "LegalCopyright" => "#{pkg.company}. All rights reserved.",
        "ProductName" => pkg.name,
        "ProductVersion" => vsn
      }
      |> Enum.flat_map(fn {key, value} -> ["--set-info", key, value] end)

    [beam] = Tooling.wildcard(rel, "**/beam.smp.dll")
    [erlexec] = Tooling.wildcard(rel, "**/erlexec.dll")

    for bin <- [new_name, beam, erlexec] do
      # Unsafe binary removal of "Erlang", needs same length!
      Tooling.file_replace(bin, "Erlang", binary_part(pkg.name <> <<0, 0, 0, 0, 0, 0>>, 0, 6))
      Tooling.cmd!(Tooling.toolpath("rel/win32/rcedit.exe"), ["/I", bin, icon])

      :ok =
        Mix.Tasks.Pe.Update.run(
          [
            "--set-subsystem",
            "IMAGE_SUBSYSTEM_WINDOWS_GUI",
            "--set-manifest",
            Path.join(build_root, "app.exe.manifest")
          ] ++ info ++ [bin]
        )
    end

    [elixir] = Tooling.wildcard(rel, "**/elixir.bat")
    Tooling.file_replace(elixir, "werl.exe", pkg.name <> ".exe")
    Tooling.file_replace(elixir, "erl.exe", pkg.name <> ".exe")
    pkg = %{pkg | priv: Map.put(pkg.priv, :executable_name, pkg.name <> ".exe")}

    redistributables = %{
      "MicrosoftEdgeWebview2Setup.exe" => "https://go.microsoft.com/fwlink/p/?LinkId=2124703",
      "vcredist_x64.exe" => "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    }

    for {redist, url} <- redistributables do
      if not File.exists?(redist) do
        Tooling.download_file(redist, url)
      end

      Tooling.base_import!(rel, redist)
    end

    # Windows has wxwidgets & openssl statically linked
    # dll_import!(rel, "C:\\msys64\\mingw64\\bin\\libgmp-10.dll")

    Tooling.wildcard(rel, "**/*.so")
    |> Enum.each(fn name ->
      new_name = Path.join(Path.dirname(name), Path.basename(name, ".so") <> ".dll")
      File.rename!(name, new_name)
    end)

    Tooling.cp!(Tooling.toolpath("rel/win32/run.vbs"), rel_path)
    content = Tooling.eval_eex(Tooling.toolpath("rel/win32/run.bat.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "run.bat"), content)

    pkg |> Result.ok()
  end
end
