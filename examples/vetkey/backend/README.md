# Nim Backend

This canister is built with `nicp build` or `nicp dev` and deployed through `icp-cli`.

## Overview

- `backend/canister.yaml` runs the Nim build script.
- `backend/config.nims` configures the WASM32/WASI toolchain.
- `backend/backend.did` defines the canister interface.

## Source Code

The entry point is [`backend/src/main.nim`](./src/main.nim).

## Notes

- サンプル実装（`controller.nim` の `VetKdKeyName`）は **`key_1`**（`icp` のローカル managed と本番の両方で利用可能な名前）を使います。
- 別のレプリカで **`test_key_1`** しか無い場合は、その環境に合わせて `VetKdKeyName` を変更してください。
