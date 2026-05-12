import std/osproc
import ./c_headers_impl


proc runStreamingCommand(command: string, args: openArray[string] = []): int =
  let process = startProcess(
    command,
    args = args,
    options = {poUsePath, poParentStreams}
  )
  result = waitForExit(process)
  close(process)


proc network*(): int =
  ## Refresh headers, stop any running dfx instance, and start the local dfx network.
  cHeaders()
  discard runStreamingCommand("dfx", ["killall"])
  return runStreamingCommand(
    "dfx",
    ["start", "--clean", "--background", "--host", "0.0.0.0:4943", "--domain", "localhost", "--domain", "0.0.0.0"]
  )
