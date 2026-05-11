# vetKD 概要

vetKD は Management Canister の `vetkd_public_key` と `vetkd_derive_key` を使って、キャニスターごとの公開鍵生成と鍵導出を行う仕組みです。

## 要点

- `vetkd_public_key` は `opt principal` の `canister_id`、`context`、`key_id` を受け取り、`public_key` を返します。
- `vetkd_derive_key` は `input`、`context`、`transport_public_key`、`key_id` を受け取り、`encrypted_key` を返します。
- `vetkd_derive_key` には cycles の添付が必要です。
- ローカル開発では `test_key_1`、mainnet / testnet では `key_1` を使います。
- `context` はアプリケーションの domain separator として固定値を使うのが安全です。

## 参考

- [Management Canister / vetKD](https://docs.internetcomputer.org/references/management-canister#vetkd-verifiable-encrypted-threshold-key-derivation)
