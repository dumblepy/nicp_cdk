import std/os
import std/osproc
import ./c_headers_impl


proc removeDirRecursive(path: string) =
  if not dirExists(path):
    return

  for kind, entry in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      removeFile(entry)
    of pcDir:
      removeDirRecursive(entry)
    else:
      discard

  removeDir(path)


proc runStreamingCommand(command: string, args: openArray[string] = []): int =
  let process = startProcess(
    command,
    args = args,
    options = {poUsePath, poParentStreams}
  )
  result = waitForExit(process)
  close(process)


proc network*(): int =
  ## Refresh headers, clear the local .icp directory, and start the local ICP network.
  let projectDir = getCurrentDir()

  cHeaders()

  if fileExists(projectDir / "icp.yaml"):
    discard runStreamingCommand("icp", ["network", "stop"])

    removeDirRecursive(projectDir / ".icp")

    return runStreamingCommand("icp", ["network", "start", "-d"])

  echo "icp.yaml not found in " & projectDir & ". Run this target from an icp-cli project root."
  return 0
