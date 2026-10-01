Stable Memory Storage
===

This document explains how stable memory storage works in NICP and how to use it
from canisters.

## Overview

Stable memory persists across canister upgrades. In NICP it is partitioned by a
single `MemoryManager` using the `MGR` layout shared with
[`nim-ic-sqlite`](https://github.com/dumblepy/nim-ic-sqlite). The manager hands
out one virtual memory per `MemoryId`, so each data structure grows
independently without any structure owning a fixed physical offset.

NICP provides these storage types:

- `StableValue[T]` for a single value
- `IcStableSeq[T]` for a sequence of values
- `IcStableTable[K, V]` for an ordered key-value store
- `IcStableHashMap[K, V]` for an exact-match hash map

All values are serialized with the custom format in
`src/nicp_cdk/storage/libs/serialization.nim`.

## MemoryIds are part of the stable schema

A `MemoryId` identifies one virtual memory. Ids `0 .. 254` are usable and
`255` is reserved as the allocation-table free marker. The manager never assigns
ids automatically: the application owns them.

> Never reuse or change the meaning of a `MemoryId` after a deployment. A
> different id opens a different (empty) region, and a data structure's own
> magic only protects against a non-empty region.

Keep the ids in one registry module so collisions are easy to see:

```nim
# storage_memory_ids.nim
import nicp_cdk/storage/memory_manager

const
  UserTableMemoryId* = newMemoryId(32)
  AuditLogMemoryId* = newMemoryId(33)
  SqliteMemoryId* = newMemoryId(40)
```

## Lifecycle

Use strict entry points so a wrong region can never be silently initialized:

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_table

var manager: MemoryManager

proc canisterInit() =
  manager = createMemoryManagerStrict(newIcStableBackend())

proc canisterPostUpgrade() =
  manager = openExistingMemoryManagerStrict(newIcStableBackend())
```

`createMemoryManagerStrict` fails unless the backing store is empty.
`openExistingMemoryManagerStrict` never writes on error and rejects a missing,
foreign, or inconsistent `MGR` image. Do not fall back to create in
`post_upgrade`.

An application may instead use the explicit mode wrapper:

```nim
import nicp_cdk/storage/memory_manager

let manager = openStableMemoryManager(newIcStableBackend(), smCreate)      # install
let reopened = openStableMemoryManager(newIcStableBackend(), smOpenExisting) # upgrade
```

## Usage

```nim
import nicp_cdk/storage/memory_manager
import nicp_cdk/storage/stable_table
import nicp_cdk/storage/stable_seq
import nicp_cdk/storage/stable_hash_map
import nicp_cdk/storage/stable_value

const
  TableMemoryId = newMemoryId(32)
  SeqMemoryId = newMemoryId(33)
  HashMemoryId = newMemoryId(34)
  ValueMemoryId = newMemoryId(35)

let manager = createMemoryManagerStrict(newIcStableBackend())

var table = initIcStableTable[string, uint64](manager.getMemory(TableMemoryId))
table["alice"] = 100

var items = initIcStableSeq[int](manager.getMemory(SeqMemoryId))
items.add(10)
items.add(20)

var sessions = initIcStableHashMap[string, string](manager.getMemory(HashMemoryId))
sessions["token-123"] = "alice"

var counter = initStableValue[uint64](manager.getMemory(ValueMemoryId))
counter.set(42)
```

Each `getMemory` result is a `StableBackend`, so `initIcStableTable`,
`initIcStableSeq`, `initIcStableHashMap` and `initStableValue` accept it
directly. A `backend.view()` is available when an explicit `StableMemoryView` is
preferred.

## One authority per managed region

A single `MGR` region must have exactly one allocator authority. Do not open two
independent `MemoryManager` instances over the same raw stable memory: both
would update the allocation table and corrupt each other's buckets.

This matters for the WASI environment. The IC WASI polyfill, when linked,
installs its own `MGR` region at physical offset 0 and grows stable memory to one
header page plus eight 128-page buckets (= **1025 pages**) during instantiation.
An application must place its manager after the prefix explicitly:

```nim
import nicp_cdk/storage/memory_manager

let backend = newIcOffsetBackend(newIcStableBackend())
let manager =
  if fresh: createMemoryManagerStrict(backend)
  else: openExistingMemoryManagerStrict(backend)
```

`newIcOffsetBackend` is tied to the IC layout, not a universal "safe offset";
re-verify it when the WASI polyfill version or build mode changes. A canister
that does not link the polyfill can pass `newIcStableBackend()` directly. Never
let the polyfill and the application each own an allocator over the same region.

## Memory Layout

### MGR header (page 0)

```
+0     magic "MGR"                         3 bytes
+3     layout version (= 1)                1 byte
+4     allocated bucket count              u16
+6     bucket size in stable pages         u16 (default 128 = 8 MiB)
+8     reserved                            32 bytes
+40    memory size in pages per MemoryId   255 * u64
+2080  bucket allocation table             32768 * u8 (owner id, 255 = free)
```

Physical buckets start on page 1. Bucket `n` of the manager lives at
`StablePageSize + n * bucketSizeInPages * StablePageSize`. A virtual memory maps
a logical offset to a physical address through the global allocation table.
Allocation is append-only; buckets are never freed or moved.

### Structure layouts

- `StableValue`: 16-byte header (`SVAL`, version, data length) at the base of
  its virtual memory, followed by the serialized value.
- `IcStableSeq`: 32-byte header (`SSEQ`, version, length, data end) followed by
  `[elemLen u32][elemBytes]` records.
- `IcStableTable`: `SBT` superblock, node pages, and key/value blobs. Keys use
  an order-preserving codec for ordered iteration and range queries.
- `IcStableHashMap`: `SHM2` header plus paged directory and bucket chains using
  incremental linear hashing.

The view layer grows the backend automatically before a write past the current
size, so structures keep their usual "write and grow" behaviour.

## Serialization Notes

- Fixed-size values are stored in little-endian byte order.
- Variable-size values (string, Principal, seq, B+Tree values) are stored as
  `length (u32) + bytes`.
- Nim objects are serialized by field order.

## Sample Project

See `examples/stable_memory` for a working canister that exposes all storage
types via update/query methods.
