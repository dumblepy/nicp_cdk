# Package

version       = "0.1.0"
author        = "@dumblepytech1 as 'medy'"
description   = "Internet Computer CDK for Nim"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim", "nims"]
bin           = @["cli/nicp", "cli/ndfx"]
backend       = "c"
binDir        = "src/bin"


# Dependencies

requires "nim >= 2.2.2"
requires "cligen >= 1.8.3"
requires "illwill >= 0.4.1"
requires "base32 >= 0.1.3"
requires "https://github.com/dumblepy/nim-rustcrypto?subdir=src/nim-rustcrypto#head"

task test, "Run tests":
  exec """testament p "tests/test_*.nim" """
  exec """testament p "tests/**/test_*.nim" """
