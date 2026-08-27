discard """
  cmd: "nim c -r -d:nicpMemoryViewOnly --skipUserCfg $file"
"""

import std/unittest
import std/options
import std/tables
import ../../src/nicp_cdk/storage/stable_table
import ../../src/nicp_cdk/storage/libs/memory_view
import ../../src/nicp_cdk/storage/libs/stable_key_codec

type InMemoryStable = ref object
  data: seq[byte]
type CompositeKey = object
  group: uint16
  id: uint16
type UserProfile = object
  id: uint64
  displayName: string
  active: bool
type StoredProfile = object
  profile: UserProfile
  labels: seq[string]
  revision: uint32

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

suite "stable B+Tree":
  test "first insert succeeds for a new table and after reopen":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableTable[uint32, string](backing.memoryView())
    tree[1'u32] = "first"
    check tree.len == 1
    check tree[1'u32] == "first"

    var reopened = initIcStableTable[uint32, string](backing.memoryView())
    reopened[2'u32] = "second"
    check reopened.len == 2
    check reopened[1'u32] == "first"
    check reopened[2'u32] == "second"

  test "custom object values persist across updates and reopen":
    let backing = InMemoryStable(data: @[])
    let original = StoredProfile(
      profile: UserProfile(id: 42'u64, displayName: "Alice", active: true),
      labels: @["owner", "verified"], revision: 1'u32
    )
    var tree = initIcStableTable[uint32, StoredProfile](backing.memoryView())
    tree[42'u32] = original
    check tree[42'u32] == original

    let updated = StoredProfile(
      profile: UserProfile(id: 42'u64, displayName: "Alice Smith", active: false),
      labels: @["owner"], revision: 2'u32
    )
    tree[42'u32] = updated
    check tree.len == 1

    var reopened = initIcStableTable[uint32, StoredProfile](backing.memoryView())
    check reopened[42'u32] == updated

  test "zero node size in an SBT superblock is rejected":
    let backing = InMemoryStable(data: @[])
    discard initIcStableTable[uint32, string](backing.memoryView())
    for index in 8 .. 11:
      backing.data[index] = 0

    try:
      discard initIcStableTable[uint32, string](backing.memoryView())
      check false
    except ValueError as error:
      check error.msg == "invalid SBT node size"

  test "split, ordered iteration, update, and reopen":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableTable[uint32, string](backing.memoryView(), cacheSlots = 0)
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

    var reopened = initIcStableTable[uint32, string](backing.memoryView())
    check reopened.len == 100
    check reopened[50'u32] == "updated"
    check reopened[100'u32] == "value-100"

  test "deterministic random upserts match a heap reference":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableTable[uint32, uint64](backing.memoryView())
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

  test "custom key codec is persisted and used for ordering":
    let backing = InMemoryStable(data: @[])
    let codec = compositeCodec()
    var tree = initIcStableTable[CompositeKey, string](backing.memoryView(), codec)
    tree[CompositeKey(group: 2, id: 1)] = "two-one"
    tree[CompositeKey(group: 1, id: 9)] = "one-nine"
    var keys: seq[CompositeKey] = @[]
    for key, _ in tree.pairs: keys.add(key)
    check keys == @[CompositeKey(group: 1, id: 9), CompositeKey(group: 2, id: 1)]
    var reopened = initIcStableTable[CompositeKey, string](backing.memoryView(), codec)
    check reopened[CompositeKey(group: 2, id: 1)] == "two-one"

  test "value codec mismatch is rejected on reopen":
    let backing = InMemoryStable(data: @[])
    var tree = initIcStableTable[uint32, string](backing.memoryView(), valueCodecId = 1)
    tree[1'u32] = "one"
    expect ValueError:
      discard initIcStableTable[uint32, string](backing.memoryView(), valueCodecId = 2)
