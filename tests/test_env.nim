discard """
  cmd: "nim c --skipUserCfg $file"
"""

import unittest
import std/os
import std/osproc
import std/strutils
import icp_network

const
  ICP_PATH = "icp"
  ENV_SAMPLE_DIR = "/application/examples/env_sample"

suite "Environment variable canister tests":
  test "local environment is returned by the canister":
    ensureIcpNetworkStarted(ENV_SAMPLE_DIR)

    let originalDir = getCurrentDir()
    try:
      setCurrentDir(ENV_SAMPLE_DIR)

      let (deployOutput, deployExitCode) = execCmdEx(ICP_PATH & " deploy -y")
      check deployExitCode == 0
      if deployExitCode == 0:
        let (callOutput, callExitCode) = execCmdEx(
          ICP_PATH & " canister call backend env '()'"
        )
        check callExitCode == 0
        check callOutput.strip() == "(\"local\")"
      else:
        echo deployOutput
    finally:
      setCurrentDir(originalDir)
