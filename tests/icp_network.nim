import std/os
import std/exitprocs

var icpNetworkStartedDir* = ""
var icpNetworkQuitRegistered* = false

proc runIcpCommand(projectDir, command: string): int =
  let currentDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let exitCode = execShellCmd(command)
    result = exitCode
  finally:
    setCurrentDir(currentDir)

proc stopIcpNetwork*(projectDir: string) =
  let code = runIcpCommand(projectDir, "icp network stop >/dev/null 2>&1")
  if code != 0:
    discard
  if icpNetworkStartedDir == projectDir:
    icpNetworkStartedDir = ""

proc startIcpNetwork*(projectDir: string) =
  let code = runIcpCommand(projectDir, "icp network start -d >/dev/null 2>&1")
  if code != 0:
    raise newException(OSError, "Failed to start icp network in " & projectDir)

proc registerIcpNetworkStop*() =
  if icpNetworkQuitRegistered:
    return

  proc cleanupIcpNetwork() {.noconv.} =
    if icpNetworkStartedDir.len > 0:
      stopIcpNetwork(icpNetworkStartedDir)

  addExitProc(cleanupIcpNetwork)
  icpNetworkQuitRegistered = true

proc ensureIcpNetworkStarted*(projectDir: string) =
  if icpNetworkStartedDir.len > 0:
    return

  startIcpNetwork(projectDir)
  icpNetworkStartedDir = projectDir
  registerIcpNetworkStop()

template withIcpNetwork*(projectDir: string, body: untyped) =
  block:
    ensureIcpNetworkStarted(projectDir)
    try:
      body
    finally:
      stopIcpNetwork(projectDir)
