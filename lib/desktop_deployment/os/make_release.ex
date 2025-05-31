defmodule DesktopDeployment.Os.MakeRelease do
  alias DesktopDeployment.Tooling

  def call(opts) do
    case Tooling.os() do
      Linux -> DesktopDeployment.Os.Linux.MakeRelease.call(opts)
      Windows -> DesktopDeployment.Os.Windows.MakeRelease.call(opts)
      Macos -> DesktopDeployment.Os.Macos.MakeRelease.call(opts)
    end
  end
end
