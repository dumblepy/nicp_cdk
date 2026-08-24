discard """
  cmd: "nim c -r -d:nicpMemoryViewOnly --skipUserCfg $file"
"""

import std/unittest
import std/tables
import ../../src/nicp_cdk/storage/libs/memory_view
import ../../src/nicp_cdk/storage/stable_hash_map

type InMemoryStable = ref object
  data: seq[byte]

proc memoryView(memory: InMemoryStable): StableMemoryView =
  initMemoryView(
    proc(): uint64 = uint64(memory.data.len),
    proc(offset, size: uint64): seq[byte] =
      if offset > uint64(memory.data.len) or size > uint64(memory.data.len) - offset:
        raise newException(ValueError, "test memory read out of bounds")
      memory.data[int(offset) ..< int(offset + size)],
    proc(offset: uint64, data: seq[byte]) =
      let endOffset = int(offset) + data.len
      if endOffset > memory.data.len: memory.data.setLen(endOffset)
      for i, value in data: memory.data[int(offset) + i] = value
  )

suite "stable hash map":
  test "incremental splits, updates, iteration, and reopen":
    let backing = InMemoryStable(data: @[])
    var table = initIcStableHashMap[uint32, string](backing.memoryView(), maxBucketLoad = 2)
    var expected = initTable[uint32, string]()
    for key in 0'u32 ..< 100'u32:
      let value = "value-" & $key
      table[key] = value
      expected[key] = value
    table[17'u32] = "updated"
    expected[17'u32] = "updated"
    check table.len == expected.len
    for key, value in expected.pairs:
      check table.hasKey(key)
      check table[key] == value
    var iterated = initTable[uint32, string]()
    for key, value in table.pairs: iterated[key] = value
    check iterated == expected

    var reopened = initIcStableHashMap[uint32, string](backing.memoryView(), maxBucketLoad = 2)
    check reopened.len == expected.len
    for key, value in expected.pairs: check reopened[key] == value

  test "clear reuses the logical arena":
    let backing = InMemoryStable(data: @[])
    var table = initIcStableHashMap[string, uint64](backing.memoryView())
    table["old"] = 1
    table.clear()
    check table.len == 0
    check not table.hasKey("old")
    table["new"] = 2
    check table["new"] == 2
