discard """
  cmd: "nim c -r -d:nicpMemoryViewOnly --skipUserCfg $file"
"""

import std/unittest
import std/options
import std/tables
import std/endians
import ../../src/nicp_cdk/storage/memory_view
import ../../src/nicp_cdk/storage/stable_btree
import ../../src/nicp_cdk/storage/stable_key_codec
import ../../src/nicp_cdk/storage/stable_table_migration
import ../../src/nicp_cdk/storage/serialization

type InMemoryStable = ref object
  data: seq[byte]
type CompositeKey = object
  group: uint16
  id: uint16

proc compositeCodec(): StableKeyCodec[CompositeKey] =
  StableKeyCodec[CompositeKey](id: 1001'u32,
    encode: proc(key: CompositeKey): seq[byte] = stableKeyEncode(key.group) & stableKeyEncode(key.id),
    decode: proc(data: openArray[byte]): CompositeKey =
      if data.len != 4: raise newException(ValueError, "invalid composite key")
      CompositeKey(group: stableKeyDecode[uint16](data.toOpenArray(0, 1)), id: stableKeyDecode[uint16](data.toOpenArray(2, 3))))

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

proc put32(data: var openArray[byte], offset: int, value: uint32) =
  var le = value
  littleEndian32(addr data[offset], addr le)
proc put64(data: var openArray[byte], offset: int, value: uint64) =
  var le = value
  littleEndian64(addr data[offset], addr le)

proc appendV1Record(data: var seq[byte], key: uint32, value: string) =
  let keyData = serialize(key)
  let valueData = serialize(value)
  let recordStart = data.len
  data.setLen(recordStart + 8 + keyData.len + valueData.len)
  data.put32(recordStart, uint32(keyData.len)); data.put32(recordStart + 4, uint32(valueData.len))
  for i, byteValue in keyData: data[recordStart + 8 + i] = byteValue
  for i, byteValue in valueData: data[recordStart + 8 + keyData.len + i] = byteValue

suite "stable B+Tree":
  test "split, ordered iteration, update, and reopen":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableBTreeMap[uint32, string](backing.memoryView(), cacheSlots = 0)
    for index in countdown(100'u32, 1'u32): tree[index] = "value-" & $index
    check tree.len == 100
    for index in 1'u32 .. 100'u32:
      check tree.hasKey(index)
      check tree[index] == "value-" & $index
    var ordered: seq[uint32] = @[]
    for key, _ in tree.pairs: ordered.add(key)
    check ordered.len == 100
    for index in 0 ..< ordered.len: check ordered[index] == uint32(index + 1)
    tree[50'u32] = "updated"
    check tree.len == 100
    check tree[50'u32] == "updated"
    let bound = tree.lowerBound(50'u32)
    check bound.isSome
    check bound.get == (50'u32, "updated")
    var ranged: seq[uint32] = @[]
    for key, _ in tree.range(40'u32, 45'u32): ranged.add(key)
    check ranged == @[40'u32, 41'u32, 42'u32, 43'u32, 44'u32]

    var reopened = initIcStableBTreeMap[uint32, string](backing.memoryView())
    check reopened.len == 100
    check reopened[50'u32] == "updated"
    check reopened[100'u32] == "value-100"

  test "deterministic random upserts match a heap reference":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableBTreeMap[uint32, uint64](backing.memoryView())
    var reference = initTable[uint32, uint64]()
    var state = 0x9E3779B97F4A7C15'u64
    for _ in 0 ..< 1000:
      state = state xor (state shl 7)
      state = state xor (state shr 9)
      let key = uint32(state mod 200'u64)
      let value = state xor (state shr 17)
      tree[key] = value
      reference[key] = value
    check tree.len == reference.len
    for key, value in reference.pairs:
      check tree.hasKey(key)
      check tree[key] == value
    var previous = none(uint32)
    for key, value in tree.pairs:
      if previous.isSome: check previous.get < key
      check reference[key] == value
      previous = some(key)

  test "v1 migration resumes and keeps the last duplicate value":
    let source = InMemoryStable(data: newSeq[byte](32))
    source.data[0] = byte('S'); source.data[1] = byte('T'); source.data[2] = byte('B'); source.data[3] = byte('L')
    source.data.put32(4, 1'u32)
    source.data.appendV1Record(1'u32, "first")
    source.data.appendV1Record(2'u32, "second")
    source.data.appendV1Record(1'u32, "latest")
    source.data.put64(16, uint64(source.data.len))
    let migrationState = InMemoryStable(data: @[])
    let destinationBacking = InMemoryStable(data: @[])
    var destination = initIcStableBTreeMap[uint32, string](destinationBacking.memoryView())
    var migration = initStableTableMigration(source.memoryView(), migrationState.memoryView())
    check migration.migrateStep(destination, 1) == 1
    check not migration.isComplete
    var resumed = initStableTableMigration(source.memoryView(), migrationState.memoryView())
    check resumed.migrateStep(destination, 10) == 2
    check resumed.isComplete
    check destination.len == 2
    check destination[1'u32] == "latest"
    check destination[2'u32] == "second"

  test "custom key codec is persisted and used for ordering":
    let backing = InMemoryStable(data: @[])
    let codec = compositeCodec()
    var tree = initIcStableBTreeMap[CompositeKey, string](backing.memoryView(), codec)
    tree[CompositeKey(group: 2, id: 1)] = "two-one"
    tree[CompositeKey(group: 1, id: 9)] = "one-nine"
    var keys: seq[CompositeKey] = @[]
    for key, _ in tree.pairs: keys.add(key)
    check keys == @[CompositeKey(group: 1, id: 9), CompositeKey(group: 2, id: 1)]
    var reopened = initIcStableBTreeMap[CompositeKey, string](backing.memoryView(), codec)
    check reopened[CompositeKey(group: 2, id: 1)] == "two-one"

  test "value codec mismatch is rejected on reopen":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableBTreeMap[uint32, string](backing.memoryView(), valueCodecId = 1)
    tree[1'u32] = "one"
    expect ValueError:
      discard initIcStableBTreeMap[uint32, string](backing.memoryView(), valueCodecId = 2)
