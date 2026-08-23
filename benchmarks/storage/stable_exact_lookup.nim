## Exact-match lookup comparison for the stable-memory-native indices.
##
## Run with:
##   nim c -d:release -d:nicpMemoryViewOnly -r --skipUserCfg benchmarks/storage/stable_exact_lookup.nim
##   nim c -d:release -d:nicpMemoryViewOnly -r --skipUserCfg benchmarks/storage/stable_exact_lookup.nim 100000
##
## Wall-clock values are environment-dependent.  The read-call and read-byte
## counters are the portable result: they model the stable-memory work that a
## canister has to perform for the workload.

import std/[monotimes, strformat, os, times, strutils]
import ../../src/nicp_cdk/storage/memory_view
import ../../src/nicp_cdk/storage/stable_btree
import ../../src/nicp_cdk/storage/stable_hash_map

type InMemoryStable = ref object
  data: seq[byte]
  readCalls, readBytes: uint64

proc memoryView(memory: InMemoryStable): StableMemoryView =
  initMemoryView(
    proc(): uint64 = uint64(memory.data.len),
    proc(offset, size: uint64): seq[byte] =
      if offset > uint64(memory.data.len) or size > uint64(memory.data.len) - offset:
        raise newException(ValueError, "benchmark memory read out of bounds")
      inc memory.readCalls
      memory.readBytes += size
      memory.data[int(offset) ..< int(offset + size)],
    proc(offset: uint64, data: seq[byte]) =
      let endOffset = int(offset) + data.len
      if endOffset > memory.data.len: memory.data.setLen(endOffset)
      for i, value in data: memory.data[int(offset) + i] = value
  )

proc resetReads(memory: InMemoryStable) =
  memory.readCalls = 0
  memory.readBytes = 0

proc queryOrder(index, count: uint32): uint32 =
  ## Deterministic, non-sequential key distribution for lookup workloads.
  uint32((uint64(index) * 2_654_435_761'u64) mod uint64(count))

proc benchmark(count: uint32) =
  let treeMemory = InMemoryStable(data: @[])
  let hashMemory = InMemoryStable(data: @[])
  var tree = initIcStableBTreeMap[uint32, uint64](treeMemory.memoryView(), cacheSlots = 0)
  var hash = initIcStableHashMap[uint32, uint64](hashMemory.memoryView())
  for key in 0'u32 ..< count:
    let value = uint64(key) xor 0x9e3779b97f4a7c15'u64
    tree[key] = value
    hash[key] = value

  treeMemory.resetReads()
  var treeChecksum = 0'u64
  let treeStart = getMonoTime()
  for index in 0'u32 ..< count:
    treeChecksum = treeChecksum xor tree[queryOrder(index, count)]
  let treeElapsed = getMonoTime() - treeStart

  hashMemory.resetReads()
  var hashChecksum = 0'u64
  let hashStart = getMonoTime()
  for index in 0'u32 ..< count:
    hashChecksum = hashChecksum xor hash[queryOrder(index, count)]
  let hashElapsed = getMonoTime() - hashStart
  doAssert treeChecksum == hashChecksum

  echo &"entries={count}"
  echo &"  btree: {inMilliseconds(treeElapsed)} ms, reads={treeMemory.readCalls}, bytes={treeMemory.readBytes}"
  echo &"  hash:  {inMilliseconds(hashElapsed)} ms, reads={hashMemory.readCalls}, bytes={hashMemory.readBytes}"

let count = if paramCount() == 1: parseUInt(paramStr(1)).uint32 else: 10_000'u32
if count == 0: raise newException(ValueError, "entry count must be positive")
benchmark(count)
