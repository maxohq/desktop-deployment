defmodule DesktopDeployment.Os.Windows.MakeRelease do
  use DesktopDeployment.Operation

  def call(pkg) do
    Operation.new()
    |> Operation.run(:first, fn -> first_action(pkg) end)
    |> IO.inspect()
    |> respond()
  end

  defp respond(result) do
    Operation.log_error(result, "Error in Windows.MakeRelease")

    case result do
      {:ok, ctx} -> {:ok, ctx.first}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end

  defp first_action(%Package{release: %Mix.Release{path: rel_path, version: vsn} = rel} = pkg) do
    build_root = Path.join([rel_path, "..", ".."]) |> Path.expand()
    signfun = win32_sign_function(pkg)

    if signfun == nil do
      Mix.Shell.IO.info("Not signing secret detected. Skipping signing")
    else
      win32_codesign(signfun, build_root)
    end

    nsi_file = Tooling.toolpath("rel/win32/app.nsi.eex")
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

    %{pkg | priv: Map.put(pkg.priv, :installer_name, outfile)} |> Result.ok()
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
end
