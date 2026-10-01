discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

import std/unittest
import ../../src/nicp_cdk/storage/memory_manager
import ../../src/nicp_cdk/storage/stable_table
import ../../src/nicp_cdk/storage/stable_seq
import ../../src/nicp_cdk/storage/stable_hash_map
import ../../src/nicp_cdk/storage/stable_value

const
  TableMemoryId = newMemoryId(32)
  SeqMemoryId = newMemoryId(33)
  HashMemoryId = newMemoryId(34)
  ValueMemoryId = newMemoryId(35)

suite "stable structures on a MemoryManager":
  test "table, seq, hash map and value share a manager and survive reopen":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw)

    var table = initIcStableTable[string, string](manager.getMemory(TableMemoryId))
    var sequence = initIcStableSeq[int](manager.getMemory(SeqMemoryId))
    var hash = initIcStableHashMap[string, int](manager.getMemory(HashMemoryId))
    var value = initStableValue[string](manager.getMemory(ValueMemoryId))

    table["one"] = "first"
    table["two"] = "second"
    sequence.add(10)
    sequence.add(20)
    hash["alpha"] = 1
    hash["beta"] = 2
    value.set("settings")

    check table["one"] == "first"
    check sequence.toSeq() == @[10, 20]
    check hash["beta"] == 2
    check value.get() == "settings"

    ## The structures must not have corrupted each other's regions.
    let reopened = openExistingMemoryManagerStrict(raw)
    var table2 = initIcStableTable[string, string](reopened.getMemory(TableMemoryId))
    var sequence2 = initIcStableSeq[int](reopened.getMemory(SeqMemoryId))
    var hash2 = initIcStableHashMap[string, int](reopened.getMemory(HashMemoryId))
    var value2 = initStableValue[string](reopened.getMemory(ValueMemoryId))

    check table2.len == 2
    check table2["two"] == "second"
    check sequence2.toSeq() == @[10, 20]
    check hash2["alpha"] == 1
    check value2.get() == "settings"

  test "view() auto-grows a virtual memory for the first write":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw)
    let memory = manager.getMemory(newMemoryId(40))
    check memory.sizePages == 0

    var table = initIcStableTable[uint32, string](memory.view())
    table[1'u32] = "one"

    check memory.sizePages >= 1
    check table[1'u32] == "one"

  test "a fresh MemoryId does not see another structure's data":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw)
    var populated = initIcStableTable[string, string](manager.getMemory(newMemoryId(50)))
    populated["key"] = "value"

    var separate = initIcStableTable[string, string](manager.getMemory(newMemoryId(51)))
    check separate.len == 0
    check not separate.hasKey("key")
