# vetKD Overview

vetKD uses the Management Canister methods `vetkd_public_key` and `vetkd_derive_key` to derive per-canister keys.

## Key points

- `vetkd_public_key` takes `opt principal canister_id`, `context`, and `key_id`, then returns `public_key`.
- `vetkd_derive_key` takes `input`, `context`, `transport_public_key`, and `key_id`, then returns `encrypted_key`.
- `vetkd_derive_key` requires attached cycles.
- Use `test_key_1` for local development and `key_1` for mainnet / testnet.
- Treat `context` as a stable domain separator for your application.

## Reference

- [Management Canister / vetKD](https://docs.internetcomputer.org/references/management-canister#vetkd-verifiable-encrypted-threshold-key-derivation)
