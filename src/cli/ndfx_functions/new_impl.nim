# import std/os
import std/strutils
import std/strformat
import std/os
import std/osproc
import std/json
import illwill


const configContent = """
import std/os

--mm: "orc"
--threads: "off"
--cpu: "wasm32"
--os: "linux"
--nomain
--cc: "clang"
--define: "useMalloc"

switch("define", "wasi")
switch("define", "rustcryptoWasi")

# Enforce static linking for the WASI target to make it self-contained, similar to icpp-pro
switch("passC", "-target wasm32-wasi")
switch("passL", "-target wasm32-wasi")
switch("passL", "-static") # Statically link necessary libraries
switch("passL", "-nostartfiles") # Do not link standard startup files
switch("passL", "-Wl,--no-entry") # Do not enforce an entry point
switch("passC", "-fno-exceptions") # Do not use exceptions

# optimize
when defined(release):
  switch("passC", "-Os") # optimize for size
  switch("passC", "-flto") # link time optimization for compiler
  switch("passL", "-flto") # link time optimization for linker

# ic0.h path
# to download, run `ndfx c_headers`
let cHeadersPath = "/root/.ic-c-headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)

# ic wasi polyfill path
let icWasiPolyfillPath = getEnv("IC_WASI_POLYFILL_PATH")
switch("passL", "-L" & icWasiPolyfillPath)
switch("passL", "-lic_wasi_polyfill")

# WASI SDK sysroot / include
let wasiSysroot = getEnv("WASI_SDK_PATH") / "share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

# WASI emulation settings
switch("passC", "-D_WASI_EMULATED_SIGNAL")
switch("passL", "-lwasi-emulated-signal")
"""

const mainCode = """
import nicp_cdk

proc greet() {.query.} =
  let request = Request.new()
  let name = request.getStr(0)
  reply("Hello, " & name & "!")
"""

const didContent = """
service : {
  greet : (text) -> (text) query;
};
"""

const internetIdentityCandidUrl =
  "https://github.com/dfinity/internet-identity/releases/download/release-2026-02-28/internet_identity.did"
const internetIdentityWasmUrl =
  "https://github.com/dfinity/internet-identity/releases/download/release-2026-02-28/internet_identity_dev.wasm.gz"

proc parseNimVersion(output: string): string =
  const marker = "Nim Compiler Version"
  for line in output.splitLines:
    let pos = line.find(marker)
    if pos >= 0:
      let rest = line[(pos + marker.len) .. ^1].strip()
      let parts = rest.splitWhitespace()
      if parts.len > 0:
        return parts[0]
  return ""

proc resolveNimVersion(): string =
  let (nimOut, nimExit) = execCmdEx("nim -v")
  if nimExit != 0:
    stderr.writeLine("Error: failed to execute `nim -v`.")
    if nimOut.len > 0:
      stderr.writeLine(nimOut)
    return ""
  result = parseNimVersion(nimOut)
  if result.len == 0:
    stderr.writeLine("Error: failed to parse Nim version from `nim -v` output.")
    if nimOut.len > 0:
      stderr.writeLine(nimOut)
  return result

proc renderNimbleContent(projectName, nimVersion: string): string =
  result = &"""# Package

version       = "0.1.0"
author        = "Anonymous"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src/{projectName}_backend"
bin           = @["main"]


# Dependencies

requires "nim >= {nimVersion}"
requires "https://github.com/itsumura-h/nicp_cdk >= 0.1.0"
"""

proc new*(args: seq[string]):int =
  ## Creates a new Nim project
  # ───────────────────────────────────────────────────────────────────────────────
  # コマンドライン引数チェック
  if args.len < 1:
    stderr.writeLine("Error: Define a project name.")
    quit(1)
  let projectName = args[0].replace(" ", "_").replace("-", "_")
  let projectPath = getCurrentDir() / projectName

  # ───────────────────────────────────────────────────────────────────────────────
  # 共通変数
  const
    frameworks = @["SvelteKit", "React", "Vue", "Vanilla JS", "No JS template", "None"]
    features   = @["Internet Identity", "Bitcoin (Regtest)", "Frontend tests"]

  # ───────────────────────────────────────────────────────────────────────────────
  # 初期化
  illwillInit(fullscreen = false)

  let termW = terminalWidth()
  let termH = terminalHeight()
  var tb = newTerminalBuffer(termW, termH)

  # ───────────────────────────────────────────────────────────────────────────────
  # ステップ1: フレームワーク選択
  var idxFW = 0
  while true:
    tb.clear()
    tb.write(2, 2, "? Select a frontend framework:")
    for i, fw in frameworks:
      if i == idxFW:
        tb.write(2, 4 + i, "> " & fw)
      else:
        tb.write(2, 4 + i, "  " & fw)
    tb.display()
    case getKey()
    of Key.Up:
      if idxFW > 0: dec idxFW
    of Key.Down:
      if idxFW < frameworks.len - 1: inc idxFW
    of Key.Enter:
      break
    else:
      discard

  let chosenFW = frameworks[idxFW]

  # ───────────────────────────────────────────────────────────────────────────────
  # ステップ2: 追加機能選択
  var selectedFeats = newSeq[bool](features.len)
  var idxFeat = 0

  while true:
    tb.clear()
    tb.write(2, 2, "? Add extra features (space to select, enter to confirm)")
    var row = 4
    # 各機能を表示（Frontend tests は条件付き）
    for i, feat in features:
      if feat == "Frontend tests" and chosenFW notin @["SvelteKit", "React", "Vue", "Vanilla JS"]:
        continue
      let mark = if selectedFeats[i]: "✓" else: " "
      if i == idxFeat:
        tb.write(2, row, "> " & mark & " " & feat)
      else:
        tb.write(2, row, "  " & mark & " " & feat)
      inc row

    tb.display()
    let key = getKey()
    case key
    of Key.Up:
      # 上に移動（存在しない行はスキップ）
      var newIdx = idxFeat - 1
      while newIdx >= 0:
        if not (features[newIdx] == "Frontend tests" and chosenFW notin @["SvelteKit", "React", "Vue"]):
          idxFeat = newIdx; break
        dec newIdx
    of Key.Down:
      # 下に移動
      var newIdx = idxFeat + 1
      while newIdx < features.len:
        if not (features[newIdx] == "Frontend tests" and chosenFW notin @["SvelteKit", "React", "Vue"]):
          idxFeat = newIdx; break
        inc newIdx
    of Key.Space:
      # チェック／アンチェック
      if not (features[idxFeat] == "Frontend tests" and chosenFW notin @["SvelteKit", "React", "Vue"]):
        selectedFeats[idxFeat] = not selectedFeats[idxFeat]
    of Key.Enter:
      break
    else:
      discard

  illwillDeinit()    # 画面制御を元に戻す
  # ───────────────────────────────────────────────────────────────────────────────

  let framework = (
    proc():string =
      case chosenFW
      of "SvelteKit": return "sveltekit"
      of "React": return "react"
      of "Vue": return "vue"
      of "Vanilla JS": return "vanilla"
      of "No JS template": return "simple-assets"
      of "None": return "none"
  )()
  var selectedFeatsList = newSeq[string]()
  for i, feat in features:
    if selectedFeats[i]:
      case feat
      of "Internet Identity":
        selectedFeatsList.add("internet-identity")
      of "Bitcoin (Regtest)":
        selectedFeatsList.add("bitcoin")
      of "Frontend tests":
        selectedFeatsList.add("frontend-tests")
  let selectedFeatsListStr = 
    if selectedFeatsList.len > 0:
      "--extras " & selectedFeatsList.join(" --extras ")
    else:
      ""

  let command = &"dfx new {projectName} --type motoko --frontend {framework} {selectedFeatsListStr}"
  let (output, exitCode) = execCmdEx(command)
  if exitCode != 0:
    echo "Error: ", output
    return 1

  let nimVersion = resolveNimVersion()
  if nimVersion.len == 0:
    return 1

  removeFile(projectPath / &"src/{projectName}_backend/main.mo")
  writeFile(projectPath / &"src/{projectName}_backend/config.nims", configContent)
  writeFile(projectPath / &"src/{projectName}_backend/main.nim", mainCode)
  writeFile(projectPath / &"{projectName}.did", didContent)
  writeFile(projectPath / &"{projectName}.nimble", renderNimbleContent(projectName, nimVersion))

  # replace dfx.json
  let buildCmd = "bash -c 'if [ \"${DFX_NETWORK:-local}\" = \"local\" ]; then ndfx development_build; else ndfx production_build; fi'"
  let dfxJson = readFile(projectPath / "dfx.json").parseJson()
  dfxJson["canisters"][&"{projectName}_backend"] = %*{
    "candid": &"{projectName}.did",
    "package": &"{projectName}_backend",
    "build": buildCmd,
    "main": &"src/{projectName}_backend/main.nim",
    "wasm": "main.wasm",
    "type": "custom",
    "metadata": [
      {
        "name": "candid:service"
      }
    ]
  }
  dfxJson["defaults"]["replica"] = %*{
    "subnet_type": "system"
  }
  dfxJson["networks"] = %*{
    "local": {
      "bind": "127.0.0.1:4943",
      "type": "ephemeral"
    }
  }
  if dfxJson.hasKey("canisters") and dfxJson["canisters"].hasKey("internet_identity"):
    dfxJson["canisters"]["internet_identity"]["candid"] = %internetIdentityCandidUrl
    dfxJson["canisters"]["internet_identity"]["wasm"] = %internetIdentityWasmUrl
  writeFile(projectPath / "dfx.json", dfxJson.pretty())