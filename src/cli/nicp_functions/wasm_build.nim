import std/os
import std/osproc


proc removeByGlob(pattern: string) =
  for path in walkFiles(pattern):
    removeFile(path)

proc findProjectRoot(startDir: string): string =
  var dir = startDir
  while true:
    if fileExists(dir / "icp.yaml") or fileExists(dir / "dfx.json"):
      return dir

    for path in walkFiles(dir / "*.nimble"):
      if splitFile(path).name != "nicp_cdk":
        return dir

    if fileExists(dir / "backend" / "canister.yaml"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  return startDir

proc resolveProjectName(projectDir: string): string =
  for pattern in [projectDir / "*.nimble", projectDir / "*.did"]:
    for path in walkFiles(pattern):
      if splitFile(path).name == "nicp_cdk":
        continue
      return splitFile(path).name
  return ""

proc resolveMainPath(projectDir: string, projectName: string): string =
  let candidates = [
    projectDir / "src" / "main.nim",
    projectDir / "backend" / "src" / "main.nim",
    projectDir / "src" / (projectName & "_backend") / "main.nim",
  ]

  for candidate in candidates:
    if fileExists(candidate):
      return candidate

  return ""

proc resolveOutputPath(projectDir: string): string =
  let outputPath = getEnv("ICP_WASM_OUTPUT_PATH")
  if outputPath.len > 0:
    return outputPath
  return projectDir / "main.wasm"

proc resolveCandidPath(projectDir, originalDir: string, projectName: string): string =
  let candidates = [
    originalDir / "backend.did",
    projectDir / "backend.did",
    projectDir / "backend" / "backend.did",
    projectDir / (projectName & ".did"),
    originalDir / (projectName & ".did"),
  ]

  for candidate in candidates:
    if fileExists(candidate):
      return candidate

  return ""

proc ensureParentDir(path: string) =
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

proc compileWasm*(release: bool, wasiTmp = "wasi.wasm"): int =
  let originalDir = getCurrentDir()
  let projectDir = findProjectRoot(originalDir)
  let projectName = resolveProjectName(projectDir)
  let mainPath = resolveMainPath(projectDir, projectName)
  let candidPath = resolveCandidPath(projectDir, originalDir, projectName)

  if mainPath.len == 0:
    stderr.writeLine(
      "Error: main.nim not found. Expected src/main.nim, backend/src/main.nim, or src/<project>_backend/main.nim in the current directory."
    )
    return 1

  var wasmOptPath = ""
  if release:
    wasmOptPath = findExe("wasm-opt")
    if wasmOptPath.len == 0:
      stderr.writeLine(
        "Error: wasm-opt was not found on PATH. Install Binaryen and make wasm-opt available on PATH."
      )
      return 1

  let outputPath = resolveOutputPath(originalDir)

  setCurrentDir(projectDir)
  defer:
    setCurrentDir(originalDir)

  removeByGlob("*.wasm")
  removeByGlob("*.wat")

  # var nimCmd = if fileExists(projectDir / (projectName & ".nimble")) and projectName != "nicp_cdk":
  #   "nimble c"
  # else:
  #   "nim c"
  var nimCmd = "nim c"
  if release:
    nimCmd &= " -d:release"
  nimCmd &= " -o:" & quoteShell(wasiTmp) & " " & quoteShell(mainPath)

  echo nimCmd
  let (nimOut, nimExit) = execCmdEx(nimCmd)
  if nimExit != 0:
    stderr.writeLine(nimOut)
    return nimExit

  if not fileExists(wasiTmp):
    stderr.writeLine("Error: build did not produce " & wasiTmp & ".")
    if nimOut.len > 0:
      stderr.writeLine(nimOut)
    return 1

  let wasi2icCmd = "wasi2ic " & quoteShell(wasiTmp) & " main.wasm"
  echo wasi2icCmd
  let (w2iOut, w2iExit) = execCmdEx(wasi2icCmd)
  if w2iExit != 0:
    stderr.writeLine(w2iOut)
    return w2iExit

  if fileExists(wasiTmp):
    removeFile(wasiTmp)

  const icWasmTmp = "main_ic_wasm.wasm"

  if release:
    let optimizeCmd = quoteShell(wasmOptPath) & " -O3 " & quoteShell("main.wasm") &
      " -o " & quoteShell(icWasmTmp)
    echo optimizeCmd
    let (optOut, optExit) = execCmdEx(optimizeCmd)
    if optExit != 0:
      stderr.writeLine(optOut)
      return optExit
    moveFile(icWasmTmp, "main.wasm")

  if release:
    let shrinkCmd = "ic-wasm main.wasm -o " & quoteShell(icWasmTmp) & " shrink"
    echo shrinkCmd
    let (shrOut, shrExit) = execCmdEx(shrinkCmd)
    if shrExit != 0:
      stderr.writeLine(shrOut)
      return shrExit
    moveFile(icWasmTmp, "main.wasm")

  if candidPath.len == 0:
    stderr.writeLine(
      "Error: backend.did not found. Expected backend.did, backend/backend.did, or <project>.did in the current project."
    )
    return 1

  let candidCmd = "ic-wasm main.wasm -o " & quoteShell(icWasmTmp) &
    " metadata candid:service -f " & quoteShell(candidPath) & " -v public"
  echo candidCmd
  let (candOut, candExit) = execCmdEx(candidCmd)
  if candExit != 0:
    stderr.writeLine(candOut)
    return candExit
  moveFile(icWasmTmp, "main.wasm")

  if outputPath != absolutePath("main.wasm"):
    ensureParentDir(outputPath)
    copyFile("main.wasm", outputPath)

  return 0
