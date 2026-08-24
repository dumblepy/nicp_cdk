discard """
  cmd: "nim c -r -d:nicpMemoryViewOnly --skipUserCfg $file"
"""

import std/unittest
import ../../src/nicp_cdk/storage/stable_seq

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
      if endOffset > memory.data.len:
        memory.data.setLen(endOffset)
      for index, value in data:
        memory.data[int(offset) + index] = value
  )

suite "stable sequence":
  test "reopens without a heap index and preserves variable-length changes":
    let backing = InMemoryStable(data: @[])
    var sequence = initIcStableSeq[string](backing.memoryView())
    sequence.add("one")
    sequence.add("two")
    sequence.add("three")
    sequence[1] = "a longer replacement"
    sequence.delete(0)

    var reopened = initIcStableSeq[string](backing.memoryView())
    check reopened.len == 2
    check reopened[0] == "a longer replacement"
    check reopened[1] == "three"
    check reopened.toSeq() == @["a longer replacement", "three"]

  test "rejects an older incompatible layout":
    let backing = InMemoryStable(data: newSeq[byte](32))
    backing.data[0] = byte('S')
    backing.data[1] = byte('S')
    backing.data[2] = byte('E')
    backing.data[3] = byte('Q')
    backing.data[4] = 1
    expect ValueError:
      discard initIcStableSeq[int](backing.memoryView())
