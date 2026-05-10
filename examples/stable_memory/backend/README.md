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
