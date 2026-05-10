# stable_memory example

This example canister exercises the stable memory storage types:

- `IcStableValue` for single values
- `IcStableSeq` for sequences
- `IcStableTable` for key-value storage

## Build and deploy

```bash
dfx stop
dfx start --clean --background --host 0.0.0.0:4943
dfx deploy
```

## Example calls

### IcStableValue

```bash
dfx canister call stable_memory_backend int_set '(42)'
dfx canister call stable_memory_backend int_get

dfx canister call stable_memory_backend string_set '("Hello ICP")'
dfx canister call stable_memory_backend string_get
```

### IcStableSeq

```bash
dfx canister call stable_memory_backend seqInt_reset
dfx canister call stable_memory_backend seqInt_set '(10)'
dfx canister call stable_memory_backend seqInt_set '(20)'
dfx canister call stable_memory_backend seqInt_get '(1)'
dfx canister call stable_memory_backend seqInt_len
dfx canister call stable_memory_backend seqInt_values
```

### IcStableTable

```bash
dfx canister call stable_memory_backend table_reset
dfx canister call stable_memory_backend table_set '("Hello")'
dfx canister call stable_memory_backend table_get

dfx canister call stable_memory_backend table_setFor '(principal "aaaaa-aa", "root")'
dfx canister call stable_memory_backend table_getFor '(principal "aaaaa-aa")'
dfx canister call stable_memory_backend table_keys
dfx canister call stable_memory_backend table_values
```

### Upgrade check

```bash
dfx canister call stable_memory_backend int_set '(99)'
dfx canister install --mode=upgrade stable_memory_backend
dfx canister call stable_memory_backend int_get
```
