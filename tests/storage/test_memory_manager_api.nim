discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/storage/test_memory_manager_api.nim

import ../../src/nicp_cdk/storage/memory_manager
import ../../src/nicp_cdk/storage/stable_table

proc apiShape() =
  let manager = createMemoryManagerStrict(newVecStableBackend())
  let users = manager.getMemory(newMemoryId(1))
  var tree = initIcStableTable[uint32, string](users)
  tree[1'u32] = "one"
  discard tree[1'u32]

static:
  doAssert compiles(apiShape())
