# Nim Backend

This canister is built with `nicp build` or `nicp dev` and deployed through `icp-cli`.

## Overview

- `backend/canister.yaml` runs the Nim build script.
- `backend/config.nims` configures the WASM32/WASI toolchain.
- `backend/backend.did` defines the canister interface.

## Source Code

The entry point is [`backend/src/main.nim`](./src/main.nim).

## Notes

- `test_key_1` is intended for local development and testing.
- Use `key_1` for mainnet and testnet deployments.
