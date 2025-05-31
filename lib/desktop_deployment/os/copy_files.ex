defmodule DesktopDeployment.Os.CopyFiles do
  alias DesktopDeployment.Tooling

  def call(opts) do
    case Tooling.os() do
      Linux -> DesktopDeployment.Os.Linux.CopyFiles.call(opts)
      Windows -> DesktopDeployment.Os.Windows.CopyFiles.call(opts)
      Macos -> DesktopDeployment.Os.Macos.CopyFiles.call(opts)
    end
  end
end
