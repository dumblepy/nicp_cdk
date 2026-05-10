# http_outcall/motoko

This example shows how to build and deploy the Motoko example with `icp-cli`.

## Overview

- [backend](./backend/): the canister logic and Candid interface

## Run It

```bash
icp network start -d
icp deploy
```

After deployment, use `icp canister call backend <method> ...` for the methods defined in `backend/backend.did`.
