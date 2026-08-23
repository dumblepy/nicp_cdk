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

Stable memory allows you to persist data across canister upgrades. The NICP CDK provides three main types for managing persistent storage:

### IcStableValue - Single Value Storage

Store a single value of a primitive type or Principal that persists across canister upgrades.

```nim
import nicp_cdk/storage/stable_value

# Create a stable storage for an integer
var intDb = initIcStableValue(int)

# Store a value
intDb.set(42)

# Retrieve the value
let value = intDb.get()
```

Supported types: `int`, `uint`, `int8`, `int16`, `int32`, `int64`, `uint8`, `uint16`, `uint32`, `uint64`, `float32`, `float64`, `bool`, `char`, `string`, `Principal`

### IcStableSeq - Persistent Sequence

Store a sequence (array) of elements that persists across canister upgrades.

```nim
import nicp_cdk/storage/stable_seq

# Create a stable sequence of integers
var seqIntDb = initIcStableSeq[int]()

# Add elements
seqIntDb.add(1)
seqIntDb.add(2)
seqIntDb.add(3)

# Access elements
let firstElement = seqIntDb[0]

# Get sequence length
let length = seqIntDb.len()

# Delete an element
seqIntDb.delete(1)

# Clear all elements
seqIntDb.clear()
```

Supported element types: primitive types and Principal

### IcStableBTreeMap - Persistent Key-Value Store

Store key-value pairs that persist across canister upgrades.

```nim
import nicp_cdk/storage/stable_btree

# Create a stable B+Tree mapping strings to integers
var scoreTable = initIcStableBTreeMap[string, uint]()

# Store a key-value pair
scoreTable["alice"] = 100
scoreTable["bob"] = 95

# Retrieve a value
let aliceScore = scoreTable["alice"]

# Check if a key exists
if scoreTable.hasKey("alice"):
  echo "Alice has a score"

# Get map size
let numPlayers = scoreTable.len()

# Iterate over all pairs
for key, value in scoreTable.pairs():
  echo key, ": ", value

# Clear all entries
scoreTable.clear()
```

Supported key types: `string`, `Principal`, and other primitive types
Supported value types: primitive types, Principal, and Nim objects

### Example: Storing Custom Objects

You can also store custom Nim objects in a stable B+Tree:

```nim
import nicp_cdk
import nicp_cdk/storage/stable_btree

type UserProfile = object
  id: uint
  name: string
  active: bool

# Create a stable B+Tree mapping principals to user profiles
var userTable = initIcStableBTreeMap[Principal, UserProfile]()

# Store a user profile
let caller = Msg.caller()
userTable[caller] = UserProfile(id: 1, name: "Alice", active: true)

# Retrieve the user profile
let profile = userTable[caller]
echo profile.name  # Output: Alice
```

### Integration with Canister Methods

Here's a practical example of using stable storage in canister update and query methods:

```nim
import nicp_cdk
import nicp_cdk/storage/stable_value

var counterDb = initIcStableValue(uint64)

proc increment() {.update.} =
  let currentValue = counterDb.get()
  counterDb.set(currentValue + 1)
  reply(currentValue + 1)

proc getCounter() {.query.} =
  let value = counterDb.get()
  reply(value)
```

### Memory Layout

Stable memory is organized as follows:
- **Header area**: Magic bytes, version, and metadata
- **Data area**: Serialized key-value pairs or sequence elements

When data needs to grow beyond available stable memory pages, the CDK automatically extends the memory using the IC's stable memory API.

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
