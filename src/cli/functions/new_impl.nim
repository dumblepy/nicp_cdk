import std/os
import std/osproc
import std/strformat
import std/strutils


const configContent = """
import std/os

--mm: "orc"
--threads: "off"
--cpu: "wasm32"
--os: "linux"
--nomain
--cc: "clang"
--define: "useMalloc"

# Enforce static linking for the WASI target to make it self-contained.
switch("passC", "-target wasm32-wasi")
switch("passL", "-target wasm32-wasi")
switch("passL", "-static")
switch("passL", "-nostartfiles")
switch("passL", "-Wl,--no-entry")
switch("passC", "-fno-exceptions")

when defined(release):
  switch("passC", "-Os")
  switch("passC", "-flto")
  switch("passL", "-flto")

let cHeadersPath = "/root/.ic-c-headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)

let icWasiPolyfillPath = getEnv("IC_WASI_POLYFILL_PATH")
switch("passL", "-L" & icWasiPolyfillPath)
switch("passL", "-lic_wasi_polyfill")

let wasiSysroot = getEnv("WASI_SDK_PATH") / "share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

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

const backendCanisterYaml = """
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/canister-yaml-schema.json

name: backend
build:
  steps:
    - type: script
      commands:
        - ndfx build
"""

const backendGitignore = """
# Various IDEs and editors
.vscode/
.idea/
**/*~

# Mac OSX temporary files
.DS_Store
**/.DS_Store

# environment variables
.env

# Nim and WASM build artifacts
.nimcache/
*.wasm
*.wat
wasi.wasm
"""

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

proc resolveUserName(): string =
  for envKey in ["USER", "LOGNAME"]:
    let value = getEnv(envKey)
    if value.len > 0:
      return value

  let (whoamiOut, whoamiExit) = execCmdEx("whoami")
  if whoamiExit == 0:
    let value = whoamiOut.strip()
    if value.len > 0:
      return value

  return "user"

proc writeTextFile(path, content: string) =
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  writeFile(path, content)

proc removeFileIfExists(path: string) =
  if fileExists(path):
    removeFile(path)

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

proc renderNimbleContent(nimVersion: string): string =
  result = &"""# Package

version       = "0.1.0"
author        = "Anonymous"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "backend/src"
bin           = @["main"]


# Dependencies

requires "nim >= {nimVersion}"
requires "https://github.com/itsumura-h/nicp_cdk >= 0.1.0"
"""

proc renderRootGitignore(): string =
  result = """
.vscode/
.idea/
**/*~

# Mac OSX temporary files
.DS_Store
**/.DS_Store

# environment variables
.env

# icp-cli local cache (safe to delete, rebuilt on next build/deploy)
.icp/cache/
# Do NOT ignore .icp/data/ - it stores mainnet canister ID mappings.

# Nim and WASM build artifacts
.nimcache/
*.wasm
*.wat
wasi.wasm

# Node.js / frontend artifacts
node_modules/
dist/
dist-ssr/
*.local
"""

proc renderIcpYaml(hasFrontend: bool): string =
  if hasFrontend:
    result = """
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/icp-yaml-schema.json

canisters:
  - backend
  - frontend
"""
  else:
    result = """
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/icp-yaml-schema.json

canisters:
  - backend
"""

proc renderBackendReadme(): string =
  result = """
# Nim Backend

This canister is built with `ndfx build` or `ndfx dev` and deployed through `icp-cli`.

## Overview

- `backend/canister.yaml` runs the Nim build script.
- `backend/config.nims` configures the WASM32/WASI toolchain.
- `backend/backend.did` defines the canister interface.

## Source Code

The entry point is [`backend/src/main.nim`](./src/main.nim).

## Build Output

When `ICP_WASM_OUTPUT_PATH` is set, the final `main.wasm` is copied there after the build finishes.
"""

proc renderRootReadme(projectName: string, hasFrontend: bool): string =
  let frontendBlock = if hasFrontend:
    """
- [frontend](./frontend/): a React webapp deployed in an asset canister.
"""
  else:
    """
"""

  let frontendRunBlock = if hasFrontend:
    """
If you want to work on the frontend, use the generated React app in [`frontend/app`](./frontend/app).
"""
  else:
    """
This project does not include a frontend canister.
"""

  result = &"""# Hello World

Welcome to your new `{projectName}` project. It demonstrates a Nim backend canister built with `ndfx` and managed by `icp-cli`.

## Overview

This project consists of one or two canisters:

- [backend](./backend/): a Nim canister with its [`backend.did`](./backend/backend.did) file.
{frontendBlock}

## Build and Deploy

First, start a local network:

```bash
icp network start -d
```

Then, deploy the project:

```bash
icp deploy
```

You can call the backend directly:

```bash
icp canister call backend greet '("Internet Computer")'
```

## Local Backend Iteration

If you want to build the backend directly, run:

```bash
cd backend
ndfx dev
```

Use `ndfx build` instead of `ndfx dev` for a release-oriented build.
Pass `none` as the second argument to `ndfx new` if you want a backend-only project.

{frontendRunBlock}
Finally, stop the local network with:

```bash
icp network stop
```
"""

proc projectScaffoldCommand(projectName: string): string =
  result = &"icp new {quoteShell(projectName)} --subfolder hello-world --define backend_type=motoko --define frontend_type=react --define network_type=Default --silent --force"

proc new*(args: seq[string]): int =
  ## Creates a new Nim project
  if args.len < 1:
    stderr.writeLine("Error: Define a project name.")
    return 1

  let projectName = args[0].replace(" ", "_").replace("-", "_")
  let projectPath = getCurrentDir() / projectName
  let hasFrontend = not (args.len >= 2 and args[1].toLowerAscii in ["none", "--no-frontend"])

  putEnv("USER", resolveUserName())

  let (output, exitCode) = execCmdEx(projectScaffoldCommand(projectName))
  if exitCode != 0:
    stderr.writeLine("Error: failed to execute `icp new`.")
    if output.len > 0:
      stderr.writeLine(output)
    return 1

  let nimVersion = resolveNimVersion()
  if nimVersion.len == 0:
    return 1

  let backendDir = projectPath / "backend"

  removeFileIfExists(backendDir / "src" / "main.mo")
  removeFileIfExists(backendDir / "mops.toml")

  writeTextFile(projectPath / "README.md", renderRootReadme(projectName, hasFrontend))
  writeTextFile(projectPath / ".gitignore", renderRootGitignore())
  writeTextFile(projectPath / "icp.yaml", renderIcpYaml(hasFrontend))
  writeTextFile(projectPath / &"{projectName}.nimble", renderNimbleContent(nimVersion))

  writeTextFile(backendDir / "config.nims", configContent)
  writeTextFile(backendDir / "src" / "main.nim", mainCode)
  writeTextFile(backendDir / "backend.did", didContent)
  writeTextFile(backendDir / "canister.yaml", backendCanisterYaml)
  writeTextFile(backendDir / ".gitignore", backendGitignore)
  writeTextFile(backendDir / "README.md", renderBackendReadme())

  if not hasFrontend:
    removeDirRecursive(projectPath / "frontend")

  return 0
