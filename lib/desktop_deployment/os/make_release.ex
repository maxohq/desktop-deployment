defmodule DesktopDeployment.Os.MakeRelease do
  alias DesktopDeployment.Tooling

  def call(pkg) do
    case Tooling.os() do
      Linux -> DesktopDeployment.Os.Linux.MakeRelease.call(pkg)
      Windows -> DesktopDeployment.Os.Windows.MakeRelease.call(pkg)
      Macos -> DesktopDeployment.Os.Macos.MakeRelease.call(pkg)
    end
  end
end
