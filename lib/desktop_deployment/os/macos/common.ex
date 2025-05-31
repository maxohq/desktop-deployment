defmodule DesktopDeployment.Os.Macos.Common do
  alias DesktopDeployment.Tooling
  require Logger

  def find_deps(object) do
    # otool -L can't handle filenames such as "webview (Alerts)"
    if String.ends_with?(object, ")") do
      []
    else
      do_find_deps(object)
    end
  end

  defp do_find_deps(object) do
    IO.inspect("********** DEPS_FOR: #{object}")

    Tooling.cmd!("otool", ["-L", object])
    |> String.split("\n")
    |> tl()
    |> Enum.map(fn row ->
      # There can be spaces in lib names so splitting on space is not good enough
      case String.split(row, "(compatibility") do
        [path | _] -> String.trim(path) |> String.trim(":")
        _other -> nil
      end
    end)
    |> Enum.filter(&is_binary/1)
  end

  def locate_uid(pem_filename) do
    cert = File.read!(pem_filename)
    cert_der = List.keyfind!(:public_key.pem_decode(cert), :Certificate, 0)

    :public_key.der_decode(:Certificate, elem(cert_der, 1))
    |> scan()
  end

  @friendly_attribute {2, 5, 4, 3}
  defp scan({:AttributeTypeAndValue, @friendly_attribute, friendly}) do
    case Regex.scan(~r/\(([^)]+)\)$/, friendly) do
      [[_full, uid]] -> [uid]
      _ -> []
    end
  end

  @uid_attribute {0, 9, 2342, 19_200_300, 100, 1, 1}
  defp scan({:AttributeTypeAndValue, @uid_attribute, uid}) do
    [String.trim(uid)]
  end

  defp scan([head | tail]), do: scan(head) ++ scan(tail)
  defp scan(tuple) when is_tuple(tuple), do: scan(Tuple.to_list(tuple))
  defp scan(_), do: []

  def find_developer_id() do
    cond do
      System.get_env("DEVELOPER_ID") != nil ->
        System.get_env("DEVELOPER_ID")

      System.get_env("MACOS_DEVELOPER_ID") != nil ->
        System.get_env("MACOS_DEVELOPER_ID")

      System.get_env("MACOS_PEM") != nil ->
        file = "tmp.pem"
        File.write!(file, System.get_env("MACOS_PEM"))
        uids = locate_uid(file) || raise "Could not locate UID in PEM"
        uid = maybe_import_pem(file, uids)

        # Caching for next call
        if uid != nil do
          System.put_env("DEVELOPER_ID", uid)
          uid
        end

      true ->
        nil
    end
  end

  def maybe_import_pem(file, uids) do
    with nil <- do_find_developer_id(uids) do
      Tooling.cmd("security", ["import", file, "-k", keychain(), "-A"])

      with nil <- do_find_developer_id(uids) do
        raise "Failed to import PEM for uid #{inspect(uids)}"
      end
    end
  end

  defp do_find_developer_id(uids) do
    ids = find_identity()
    Enum.find(uids, fn uid -> String.contains?(ids, uid) end)
  end

  defp find_identity() do
    Tooling.cmd("security", ["find-identity", "-v", keychain()])
  end

  @keychain_key {__MODULE__, :keychain}
  defp keychain() do
    keychain = :persistent_term.get(@keychain_key, nil)

    if keychain != nil do
      keychain
    else
      keychain =
        case System.get_env("MACOS_KEYCHAIN") do
          nil -> Tooling.cmd("security", ["login-keychain"]) |> String.trim() |> String.trim("\"")
          keychain -> keychain
        end

      case Tooling.cmd_raw("security", ["show-keychain-info", keychain]) do
        {_, 36} ->
          raise "Keychain #{keychain} is not unlocked run `security unlock-keychain #{keychain}` to unlock it and try again"

        {_, 50} ->
          Logger.info("Keychain #{keychain} does not exist, creating it")
          Tooling.cmd!("security", ["create-keychain", "-p", "", keychain])

        {_, 0} ->
          :ok

        {ret, status} ->
          raise "Unknown error (#{status}) '#{ret}' when accessing keychain #{keychain}"
      end

      :persistent_term.put(@keychain_key, keychain)
      keychain
    end
  end
end
