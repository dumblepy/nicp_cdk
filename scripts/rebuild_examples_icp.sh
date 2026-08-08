#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/examples.bk"
DST="$ROOT/examples"

write_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
$*
EOF
}

write_template_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

root_gitignore=$(cat <<'EOF'
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
EOF
)

nim_backend_config=$(cat <<'EOF'
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
EOF
)

nim_backend_canister=$(cat <<'EOF'
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/canister-yaml-schema.json

name: backend
build:
  steps:
    - type: script
      commands:
        - nicp build
EOF
)

motoko_backend_canister=$(cat <<'EOF'
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/canister-yaml-schema.json

name: backend
recipe:
  type: "@dfinity/motoko@v4.1.0"
  configuration:
    main: src/main.mo
    candid: backend.did
EOF
)

backend_readme=$(cat <<'EOF'
# Nim Backend

This canister is built with `nicp build` or `nicp dev` and deployed through `icp-cli`.

## Overview

- `backend/canister.yaml` runs the Nim build script.
- `backend/config.nims` configures the WASM32/WASI toolchain.
- `backend/backend.did` defines the canister interface.

## Source Code

The entry point is [`backend/src/main.nim`](./src/main.nim).

## Build Output

When `ICP_WASM_OUTPUT_PATH` is set, the final `main.wasm` is copied there after the build finishes.
EOF
)

root_readme() {
  local project="$1"
  local kind="$2"
  cat <<EOF
# ${project}

This example shows how to build and deploy the ${kind} example with \`icp-cli\`.

## Overview

- [backend](./backend/): the canister logic and Candid interface

## Run It

\`\`\`bash
icp network start -d
icp deploy
\`\`\`

After deployment, use \`icp canister call backend <method> ...\` for the methods defined in \`backend/backend.did\`.
EOF
}

root_icp_yaml() {
  cat <<'EOF'
# yaml-language-server: $schema=https://github.com/dfinity/icp-cli/raw/refs/tags/v0.1.0/docs/schemas/icp-yaml-schema.json

canisters:
  - backend
EOF
}

root_nimble() {
  local project="$1"
  cat <<EOF
# Package

version       = "0.1.0"
author        = "Anonymous"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "backend/src"
bin           = @["main"]


# Dependencies

requires "nim >= $(nim -v | awk '/Nim Compiler Version/{print $4; exit}')"
requires "https://github.com/dumblepy/nicp_cdk >= 0.1.0"
EOF
}

create_nim_backend_project() {
  local project="$1"
  local source_dir="$2"
  local did_file="$3"
  local project_name
  project_name="$(basename "$project")"

  local target="$DST/$project"
  mkdir -p "$target/backend/src"

  cp "$did_file" "$target/backend/backend.did"
  for file in "$source_dir"/*.nim; do
    [[ -e "$file" ]] || continue
    [[ "$(basename "$file")" == "config.nims" ]] && continue
    cp "$file" "$target/backend/src/"
  done
  write_template_file "$target/backend/config.nims" <<<"$nim_backend_config"
  write_template_file "$target/backend/canister.yaml" <<<"$nim_backend_canister"
  write_template_file "$target/backend/README.md" <<<"$backend_readme"
  write_template_file "$target/.gitignore" <<<"$root_gitignore"
  write_template_file "$target/icp.yaml" <<<"$(root_icp_yaml)"
  write_template_file "$target/${project_name}.nimble" <<<"$(root_nimble "$project_name")"
  write_template_file "$target/README.md" <<<"$(root_readme "$project" "Nim backend")"
}

create_motoko_project() {
  local project="$1"
  local source_dir="$2"
  local did_content="$3"

  local target="$DST/$project"
  mkdir -p "$target/backend/src"

  cp "$source_dir"/main.mo "$target/backend/src/main.mo"
  write_template_file "$target/backend/backend.did" <<<"$did_content"
  write_template_file "$target/backend/mops.toml" <<<"[toolchain]
moc = \"1.3.0\""
  write_template_file "$target/backend/canister.yaml" <<<"$motoko_backend_canister"
  write_template_file "$target/.gitignore" <<<"$root_gitignore"
  write_template_file "$target/icp.yaml" <<<"$(root_icp_yaml)"
  write_template_file "$target/README.md" <<<"$(root_readme "$project" "Motoko")"
}

mkdir -p "$DST"

create_nim_backend_project "arg_msg_reply" "$SRC/arg_msg_reply/src/arg_msg_reply_backend" "$SRC/arg_msg_reply/arg_msg_reply.did"
create_nim_backend_project "counter" "$SRC/counter/src/counter_backend" "$SRC/counter/counter.did"
create_motoko_project "dfx_hello" "$SRC/dfx_hello/src/dfx_hello_backend" 'service : { greet : (text) -> (text) query; };'
create_nim_backend_project "ecdsa_args" "$SRC/ecdsa_args/src/ecdsa_args_backend" "$SRC/ecdsa_args/ecdsa_args.did"
create_nim_backend_project "stable_memory" "$SRC/stable_memory/src/stable_memory_backend" "$SRC/stable_memory/stable_memory.did"
create_nim_backend_project "http_outcall/nim" "$SRC/http_outcall/nim/src/nim_backend" "$SRC/http_outcall/nim/nim.did"
create_motoko_project "http_outcall/motoko" "$SRC/http_outcall/motoko/src/motoko_backend" 'service : { };'
create_nim_backend_project "type_test/nim" "$SRC/type_test/nim/src/nim_backend" "$SRC/type_test/nim/nim.did"
create_motoko_project "type_test/motoko" "$SRC/type_test/motoko/src/motoko_backend" 'service : { };'
