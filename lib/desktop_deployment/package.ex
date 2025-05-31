defmodule DesktopDeployment.Package do
  @moduledoc false
  alias DesktopDeployment.Package
  alias DesktopDeployment.Tooling
  require Logger

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

  def copy_extra_files(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    vm_args = toolpath("rel/vm.args.eex")
    content = Tooling.eval_eex(vm_args, rel, pkg)
    vm_args_out = Path.join([rel_path, "releases", vsn, "vm.args"])
    File.write!(vm_args_out, content)

    copy_extra_files(Tooling.os(), pkg)
  end

  defp copy_extra_files(
         Windows,
         %Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg
       ) do
    # Windows renaming exectuable
    [erl] = Tooling.wildcard(rel, "**/erl.exe")
    new_name = Path.join(Path.dirname(erl), pkg.name <> ".exe")
    File.rename!(erl, new_name)

    # Updating icon
    Tooling.cmd!("magick", ["convert", "-resize", "64x64", pkg.icon, "icon.ico"])

    Tooling.priv_import!(pkg, "icon.ico", strip: false)

    icon = Path.join(Tooling.priv(pkg), "icon.ico")
    content = Tooling.eval_eex(toolpath("rel/win32/app.exe.manifest.eex"), rel, pkg)
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
      Tooling.cmd!(toolpath("rel/win32/rcedit.exe"), ["/I", bin, icon])

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

    Tooling.cp!(toolpath("rel/win32/run.vbs"), rel_path)
    content = Tooling.eval_eex(toolpath("rel/win32/run.bat.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "run.bat"), content)

    pkg
  end

  defp copy_extra_files(os, %Package{release: %Mix.Release{} = rel} = pkg)
       when os in [Linux, MacOS] do
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

    if os == Linux do
      Package.Linux.import_extra_files(pkg)
    else
      Package.MacOS.import_extra_files(pkg)
    end
  end

  def create_installer(%Package{} = pkg) do
    case Tooling.os() do
      MacOS -> Package.MacOS.release(pkg)
      Linux -> linux_release(pkg)
      Windows -> windows_release(pkg)
    end
  end

  defp windows_release(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    signfun = win32_sign_function(pkg)

    if signfun == nil do
      Mix.Shell.IO.info("Not signing secret detected. Skipping signing")
    else
      win32_codesign(signfun, build_root)
    end

    nsi_file = toolpath("rel/win32/app.nsi.eex")
    {:ok, cur} = :file.get_cwd()
    :file.set_cwd(String.to_charlist(rel_path))

    content = Tooling.eval_eex(nsi_file, rel, pkg)
    File.write!(Path.join(build_root, "app.nsi"), content)
    Tooling.cmd!("makensis", ["-NOCD", "-DVERSION=#{vsn}", Path.join(build_root, "app.nsi")])
    :file.set_cwd(cur)
    outfile = "#{pkg.name}-#{vsn}.exe"

    if signfun != nil do
      path = Path.join([build_root, outfile])
      signfun.(path)
    end

    %{pkg | priv: Map.put(pkg.priv, :installer_name, outfile)}
  end

  defp linux_release(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    arch = Tooling.arch()
    out_file = Path.join(build_root, "#{pkg.name}-#{vsn}-linux-#{arch}.run")

    File.rm(out_file)

    content = Tooling.eval_eex(toolpath("rel/linux/install.eex"), rel, pkg)
    File.write!(Path.join(rel_path, "install"), content)
    File.chmod!(Path.join(rel_path, "install"), 0o755)

    run_content = Tooling.eval_eex(toolpath("rel/linux/run.eex"), rel, pkg)
    File.write!(Path.join(rel_path, pkg.name), run_content)
    File.chmod!(Path.join(rel_path, pkg.name), 0o755)

    # Remove the original release bin/ dir
    File.rm_rf!(Path.join(rel_path, "bin"))

    :file.set_cwd(String.to_charlist(rel_path))

    Tooling.cmd!(toolpath("rel/linux/makeself.sh"), [
      "--xz",
      "--threads",
      "0",
      rel_path,
      out_file,
      pkg.name,
      "./install"
    ])

    %{pkg | priv: Map.put(pkg.priv, :installer_name, out_file)}
  end

  def win32_codesign(signfun, root) do
    exceptions = [
      "msvcr120.dll",
      "msvcp120.dll",
      "webview2loader.dll",
      "vcruntime140_clr0400.dll",
      "microsoftedgewebview2setup.exe",
      "vcredist_x64.exe"
    ]

    to_sign =
      (Tooling.wildcard(root, "**/*.exe") ++ Tooling.wildcard(root, "**/*.dll"))
      |> Enum.reject(fn filename -> String.downcase(Path.basename(filename)) in exceptions end)

    File.write!("codesign.log", Enum.join(to_sign, "\n"))

    for file <- to_sign do
      signfun.(file)
    end
  end

  def win32_sign_function(%Package{name: name, name_long: name_long}) do
    app_name = name_long || name
    cert_path = Path.absname(System.get_env("WIN32_CERTIFICATE_PATH", "rel/win32/app_cert.pem"))
    key_path = Path.absname(System.get_env("WIN32_KEY_PATH", "rel/win32/app_key.pem"))

    token = System.get_env("WIN32_SAFENET_TOKEN")
    pass = System.get_env("WIN32_KEY_PASS")

    signfun =
      cond do
        pass != nil -> &win32_certificate_sign(app_name, cert_path, key_path, pass, &1)
        token != nil -> &win32_keyfob_sign(app_name, cert_path, token, &1)
        true -> nil
      end

    if signfun != nil do
      fn filename ->
        IO.puts("Signing #{filename}")
        signfun.(filename)
        File.rename!("#{filename}.tmp", filename)
        # There is a funny comment about waiting between signing requests
        # on the official microsoft docs, so we're doing that here.
        Process.sleep(5_000)
      end
    end
  end

  def win32_certificate_sign(app_name, cert_path, key_path, pass, filename) do
    # app.pem from sectigo cert `openssl x509 -in app_cert.p12 -inform DER -out app_cert.pem`
    # app_key.pem from sectigo
    Tooling.cmd!("osslsigncode", [
      "sign",
      "-certs",
      cert_path,
      "-key",
      key_path,
      "-pass",
      pass,
      "-n",
      app_name,
      "-t",
      "https://timestamp.sectigo.com",
      "-in",
      filename,
      "-out",
      "#{filename}.tmp"
    ])
  end

  def win32_keyfob_sign(app_name, cert_path, token, filename) do
    # pkcs11.so from  https://github.com/OpenSC/libp11.git @ b02940e7dcde8026a3e120fdf42921b06e8f9ee9
    # libeToken.so.10 from https://support.globalsign.com/ssl/ssl-certificates-installation/safenet-drivers
    # app.der from `pkcs11-tool --module /usr/lib/libeToken.so --id 0ff482e6569909c51ef69aabe88c659e89c32a27 --read-object --type cert --output-file app.der`
    # app.pem from `openssl x509 -in app.der -inform DER -out app.pem`
    Tooling.cmd!(
      "osslsigncode",
      [
        "sign",
        "-verbose",
        "-pkcs11engine",
        "#{System.user_home!()}/projects/libp11/src/.libs/pkcs11.so",
        "-pkcs11module",
        "/usr/lib/libeToken.so.10",
        "-h",
        "sha256",
        "-n",
        app_name,
        "-t",
        "https://timestamp.sectigo.com",
        "-certs",
        cert_path,
        "-pass",
        token,
        "-in",
        filename,
        "-out",
        "#{filename}.tmp"
      ]
    )
  end

  def toolpath(name) do
    if File.exists?(name) do
      Path.absname(name)
    else
      base = Mix.Project.deps_paths()[:desktop_deployment]
      path = Path.absname(Path.join(base, name))

      if not File.exists?(path) do
        raise "Tool #{name} not found"
      end

      path
    end
  end
end
