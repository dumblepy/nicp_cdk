# vetkey

This example shows how to build and deploy the Nim backend example with `icp-cli`.

It uses `test_key_1` for local development and testing. For mainnet or testnet, switch to `key_1`.

## Overview

- [backend](./backend/): the canister logic and Candid interface

## Run It

```bash
icp network start -d
icp deploy
```

After deployment, use `icp canister call backend <method> ...` for the methods defined in `backend/backend.did`.
