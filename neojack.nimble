# Package
version       = "0.1.1"
author        = "afolou"
description   = "njackd - JACK Audio Connection Kit Manager Daemon"
license       = "MIT"
srcDir        = "src"
bin           = @["njackd", "njackctl"]

requires "jacket"

task test, "Run tests":
  exec "nim c -r tests/test_neojack.nim"
