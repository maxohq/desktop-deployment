defmodule DesktopDeployment.Os.Windows.CopyFiles do
  use DesktopDeployment.Operation

  def call(opts \\ []) do
    Operation.new()
    |> Operation.run(:installer_path, fn -> Result.ok(nil) end)
    |> IO.inspect()
    |> respond()
  end

  defp respond(result) do
    case result do
      {:ok, ctx} -> {:ok, ctx.installer_path}
      {:error, :operation, _} -> {:error, :internal_server_error}
      _ -> {:error, :internal_server_error}
    end
  end
end
