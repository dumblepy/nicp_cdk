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
  var lastCode = -1
  for attempt in 0..2:
    lastCode = runIcpCommand(projectDir, "nicp network >/dev/null 2>&1")
    if lastCode == 0:
      return
    sleep(1000)
  raise newException(OSError, "Failed to start icp network in " & projectDir & " (exit code " & $lastCode & ")")

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

template withRestartedIcpNetwork*(projectDir: string, body: untyped) =
  block:
    stopIcpNetwork(projectDir)
    ensureIcpNetworkStarted(projectDir)
    try:
      body
    finally:
      stopIcpNetwork(projectDir)
