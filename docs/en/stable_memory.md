Stable Memory Storage
===

This document explains how the stable memory storage types work in NICP and how
to use them from canisters.

## Overview

Stable memory persists across canister upgrades. NICP provides three storage
types built on top of stable memory:

- `IcStableValue[T]` for a single value
- `IcStableSeq[T]` for a sequence of values
- `IcStableTable[K, V]` for an ordered key-value store

All values are serialized with the custom format in
`src/nicp_cdk/storage/libs/serialization.nim`.

## Usage

### IcStableValue

```nim
import nicp_cdk/storage/stable_value

var counter = initIcStableValue(uint64)
counter.set(42)
let current = counter.get()
```

### IcStableSeq

```nim
import nicp_cdk/storage/stable_seq

var items = initIcStableSeq[int]()
items.add(10)
items.add(20)
items[1] = 25
items.delete(0)
let length = items.len()
```

### IcStableTable

```nim
import nicp_cdk/storage/stable_table

var table = initIcStableTable[string, uint64]()
table["alice"] = 100
if table.hasKey("alice"):
  echo table["alice"]
```

## Memory Layout

All structures use a fixed-size header followed by a data area. The `baseOffset`
parameter lets you place multiple structures in the same stable memory region
by choosing different offsets.

### IcStableValue layout

Header size: 16 bytes.

```
0..3   magic "SVAL"
4..7   version (u32, little-endian)
8..15  data length (u64, little-endian)
16..   data bytes (serialized value)
```

### IcStableSeq layout

Header size: 32 bytes.

```
0..3   magic "SSEQ"
4..7   version 2 (u32, little-endian)
8..15  length (u64, little-endian)
16..23 data end offset (u64, little-endian)
24..31 reserved
32..   entries: [elemLen u32][elemBytes] ...
```

`IcStableSeq` opens by reading only this header. It does not rebuild a heap
array of element offsets; indexed operations locate records directly in stable
memory, and variable-length updates or deletions move data with a bounded
buffer.

### IcStableTable layout

The B+Tree persists an `SBT2` superblock, node pages, and key/value blobs.
Initialization reads only the superblock and bounded cache metadata; it does
not rebuild an in-memory index by scanning all entries.

```
0..3   magic "SBT2"
4..    versioned superblock, root address, count, allocator metadata
...    fixed-size B+Tree node pages and variable key/value blobs
```

Entries are searched directly in stable memory. Keys are stored with an
order-preserving codec, allowing ordered iteration and range queries.

## Serialization Notes

- Fixed-size values are stored in little-endian byte order.
- Variable-size values (string, Principal, seq, B+Tree values) are stored as
  `length (u32) + bytes`.
- Nim objects are serialized by field order.

## Sample Project

See `examples/stable_memory` for a working canister that uses all three storage
types and exposes them via update/query methods.
