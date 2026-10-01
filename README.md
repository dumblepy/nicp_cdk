NICP - Nim CDK for the Internet Computer (Beta)
===

This is the Nim CDK for the Internet Computer.

## Why Nim for ICP canisters?

I chose Nim for developing ICP canisters because:
- Nim can be transpiled to C, which allows it to target WebAssembly (WASM).
- Nim is a high-level language, making it as easy to write and read as Python.
- Nim is a statically typed language.
- Nim has a package manager, which makes it easy to install and manage dependencies.
- Nim has one of the best memory management systems: the compiler automatically controls the lifetime of variables without garbage collection (GC) or manual memory management.

Another motivational essay:  
[The Strength in Simplicity: The Aesthetics of Japanese Traditional Crafts and Distributed Systems](./docs/en/strength_in_simplicity.md)

## Requirements

- [Nim](https://nim-lang.org)  
- [WASI SDK (includes Clang)](https://github.com/WebAssembly/wasi-sdk)  
- [ic-wasi-polyfill](https://github.com/wasm-forge/ic-wasi-polyfill)  
- [wasi2ic](https://github.com/wasm-forge/wasi2ic)  
- [Binaryen (`wasm-opt`)](https://github.com/WebAssembly/binaryen) (required for production builds)
- [Internet Computer SDK](https://internetcomputer.org/docs/current/developer-docs/setup/install/sdk-install)  

### Optional

- [Nim language server](https://github.com/nim-lang/langserver) (recommended for Nim development)  
- [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt)  
- [Rust](https://www.rust-lang.org) (for building ic-wasi-polyfill)

## Installation

See also [Dockerfile](docker/app/develop.Dockerfile).

These instructions assume Ubuntu or Debian:

```sh
apt install -y \
  build-essential \
  libunwind-dev \
  lldb \
  lld \
  gcc-multilib \
  xz-utils \
  wget \
  curl \
  git \
  binaryen
```

### Install Rust
https://www.rust-lang.org/tools/install

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Build ic-wasi-polyfill

```sh
cd /root
git clone https://github.com/wasm-forge/ic-wasi-polyfill.git
cd ic-wasi-polyfill
rustup target add wasm32-wasip1
cargo build --release --target wasm32-wasip1
export IC_WASI_POLYFILL_PATH "/root/ic-wasi-polyfill/target/wasm32-wasip1/release"
```

### Install WASI SDK
https://github.com/WebAssembly/wasi-sdk

```sh
cd /root
WASI_VERSION="25"
WASI_VERSION_FULL="$WASI_VERSION.0"
curl -L -o wasi-sdk.tar.gz https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_VERSION}/wasi-sdk-${WASI_VERSION_FULL}-x86_64-linux.tar.gz
tar -xzf wasi-sdk.tar.gz
rm wasi-sdk.tar.gz
mv "wasi-sdk-${WASI_VERSION_FULL}-x86_64-linux" ".wasi-sdk"
export WASI_SDK_PATH "/root/.wasi-sdk"
PATH $PATH:"${WASI_SDK_PATH}/bin"
```

### Install wasi2ic
https://github.com/wasm-forge/wasi2ic

```sh
cargo install wasi2ic
```

### Install Nim
https://nim-lang.org/install.html

```sh
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

### Install NICP

```sh
nimble install https://github.com/dumblepy/nicp_cdk
```

Now you can use the `nicp` command.

## Create a new project

### Download c headers

```sh
nicp c_headers
```
`/root/.ic-c-headers` will be created.


### Create a new project

```sh
nicp new hello
cd hello
```

Use `nicp new hello none` if you want a backend-only project.

> [!WARNING]  
> Check the `hello/backend/config.nims` file:  
> - Is the `ic wasi polyfill path` correct?  
> - Is the `WASI SDK sysroot` correct?  

### Run a local network and deploy

```sh
icp network start -d
icp deploy
```

If you want to call the backend directly, use:

```sh
icp canister call backend greet '("Internet Computer")'
```

## Stable memory

Stable memory allows you to persist data across canister upgrades. The NICP CDK
partitions stable memory with a single `MemoryManager` that uses the `MGR`
layout shared with [`nim-ic-sqlite`](https://github.com/dumblepy/nim-ic-sqlite).
The manager hands out one virtual memory per `MemoryId`, so each structure grows
independently and application code never manages physical offsets.

### MemoryManager and MemoryId

A `MemoryId` is part of your application's stable schema. Valid ids are
`0 .. 254`; `255` is reserved as the allocation-table free marker. A `MemoryId`
is never assigned automatically.

> Never reuse or change the meaning of a `MemoryId` after a deployment. A
> different id opens a different (empty) region; a structure's own magic only
> protects against a non-empty region.

Keep the ids in one registry module so collisions are visible:

```nim
# storage_memory_ids.nim
import nicp_cdk/storage/memory_manager

const
  UserTableMemoryId* = newMemoryId(32)
  AuditLogMemoryId* = newMemoryId(33)
  SqliteMemoryId* = newMemoryId(40)
```

### Lifecycle: fresh install vs. upgrade

Use the strict entry points. `createMemoryManagerStrict` requires an empty
backing store, and `openExistingMemoryManagerStrict` never writes on error and
rejects a missing, foreign, or inconsistent `MGR` image.

```nim
import nicp_cdk/storage/memory_manager

var manager: MemoryManager

proc canisterInit() =
  manager = createMemoryManagerStrict(newIcStableBackend())

proc canisterPostUpgrade() =
  manager = openExistingMemoryManagerStrict(newIcStableBackend())
```

Never fall back to create in `post_upgrade`. If your application needs one code
path, use the explicit mode wrapper:

```nim
let manager = openStableMemoryManager(newIcStableBackend(), smCreate)
let reopened = openStableMemoryManager(newIcStableBackend(), smOpenExisting)
```

### IcStableValue - Single Value Storage

Store a single value of a primitive type or Principal.

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_value

const IntMemoryId = newMemoryId(32)
let manager = createMemoryManagerStrict(newIcStableBackend())

var intDb = initStableValue[int](manager.getMemory(IntMemoryId))
intDb.set(42)
let value = intDb.get()
```

Supported types: `int`, `uint`, `int8`, `int16`, `int32`, `int64`, `uint8`, `uint16`, `uint32`, `uint64`, `float32`, `float64`, `bool`, `char`, `string`, `Principal`

### IcStableSeq - Persistent Sequence

Store a sequence (array) of elements.

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_seq

const SeqMemoryId = newMemoryId(33)
let manager = createMemoryManagerStrict(newIcStableBackend())

var seqIntDb = initIcStableSeq[int](manager.getMemory(SeqMemoryId))
seqIntDb.add(1)
seqIntDb.add(2)
seqIntDb.add(3)
let firstElement = seqIntDb[0]
let length = seqIntDb.len()
seqIntDb.delete(1)
seqIntDb.clear()
```

Supported element types: primitive types and Principal

### IcStableTable - Persistent Key-Value Store

Store key-value pairs in an ordered B+Tree.

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_table

const TableMemoryId = newMemoryId(34)
let manager = createMemoryManagerStrict(newIcStableBackend())

var scoreTable = initIcStableTable[string, uint](manager.getMemory(TableMemoryId))
scoreTable["alice"] = 100
scoreTable["bob"] = 95
let aliceScore = scoreTable["alice"]
if scoreTable.hasKey("alice"):
  echo "Alice has a score"
let numPlayers = scoreTable.len()
for key, value in scoreTable.pairs():
  echo key, ": ", value
scoreTable.clear()
```

Supported key types: `string`, `Principal`, and other primitive types
Supported value types: primitive types, Principal, and Nim objects

#### Choosing between IcStableTable and IcStableHashMap

Both are key-value stores persisted in stable memory, but they use different
index structures. In most cases, choose `IcStableTable` when you need ordered
iteration or range queries.

| Type | Index | Best for | Ordered APIs |
| --- | --- | --- | --- |
| `IcStableTable[K, V]` | B+Tree | General-purpose KV storage, ordered iteration, and range queries | `pairs`, `lowerBound`, `range` |
| `IcStableHashMap[K, V]` | Linear hashing | Exact-match workloads dominated by `get` and `hasKey` | None (`pairs` order is unspecified) |

`IcStableHashMap` splits one bucket at a time as it grows, avoiding a full
rehash in a single operation. It does not preserve key order, so use
`IcStableTable` whenever you need range queries.

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_hash_map

const HashMemoryId = newMemoryId(35)
let manager = createMemoryManagerStrict(newIcStableBackend())

var sessionByToken = initIcStableHashMap[string, string](manager.getMemory(HashMemoryId))
sessionByToken["token-123"] = "alice"
if sessionByToken.hasKey("token-123"):
  echo sessionByToken["token-123"]
for token, user in sessionByToken.pairs():
  # Iteration order is unspecified.
  echo token, ": ", user
```

### Example: Storing Custom Objects

You can also store custom Nim objects in a stable B+Tree:

```nim
import nicp_cdk
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_table

type UserProfile = object
  id: uint
  name: string
  active: bool

const UserTableMemoryId = newMemoryId(36)
let manager = createMemoryManagerStrict(newIcStableBackend())

var userTable = initIcStableTable[Principal, UserProfile](manager.getMemory(UserTableMemoryId))
let caller = Msg.caller()
userTable[caller] = UserProfile(id: 1, name: "Alice", active: true)
let profile = userTable[caller]
echo profile.name  # Output: Alice
```

### One allocator authority per managed region

A single `MGR` region must have exactly one allocator authority. Do not open two
independent `MemoryManager` instances over the same raw stable memory: both
would update the allocation table and corrupt each other's buckets.

This matters for the WASI environment. The IC WASI polyfill, when linked,
installs its own `MGR` region at physical offset 0 and grows stable memory to
one header page plus eight 128-page buckets (= **1025 pages**) during
instantiation. An application must place its manager after that prefix with the
explicit helper:

```nim
import nicp_cdk/storage/memory_manager

let backend = newIcOffsetBackend(newIcStableBackend())
let manager =
  if fresh: createMemoryManagerStrict(backend)
  else: openExistingMemoryManagerStrict(backend)
```

`newIcOffsetBackend` is an explicit partition, not an implicit "safe offset". It
is tied to the IC layout, so re-verify it when the WASI polyfill version or
build mode changes. A canister that does not link the polyfill can pass
`newIcStableBackend()` directly. Never let the polyfill and the application each
own an allocator over the same region.

### Memory Layout

Stable memory is organized as follows:

- **Page 0**: `MGR` manager header (magic, version, bucket size, per-id sizes,
  and the global bucket allocation table).
- **Page 1+**: physical buckets. Bucket `n` lives at
  `StablePageSize + n * bucketSizeInPages * StablePageSize`.
- Each `MemoryId` is a virtual memory mapped onto those buckets.

Allocation is append-only; buckets are never freed or moved. When a write grows
past the end of a virtual memory, the view adapter grows the backend first.

### Serialization

The NICP CDK uses a custom, efficient serialization format optimized for stable memory:
- **Fixed-size types** (integers, floats, bools): Stored directly as little-endian bytes
- **Variable-size types** (strings, Principal): Prefixed with a 4-byte length field, followed by the data

This approach is more efficient than Candid encoding, which includes type information in the serialized data.

### See Also

For a complete working example, see [examples/stable_memory](examples/stable_memory).
For detailed storage and layout notes, see [docs/en/stable_memory.md](docs/en/stable_memory.md).

## Roadmap

- [ ] No need to manually build ic-wasi-polyfill.  
- [X] Support all IC types.  
- [X] Access and call the management canister.  
- [X] HTTP outcall example.  
- [X] Stable memory.  
- [X] t-ECDSA example.  
- [ ] t-RSA example.  
- [ ] Bitcoin example.  
- [X] Ethersum example.  
- [ ] Solana example.  
- [ ] VetKey example.
