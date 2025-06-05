defmodule CodesignTest do
  use ExUnit.Case

  test "codesign a new binary" do
    {_, 0} = System.cmd("gcc", ["test/priv/main.c", "-o", "unsigned_main"])
    DesktopDeployment.Os.Macos.MakeRelease.codesign_executable("unsigned_main")
    File.rm("unsigned_main")
  end
end
