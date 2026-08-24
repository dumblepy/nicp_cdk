discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/storage/test_memory_manager_api.nim

import ../../src/nicp_cdk/storage/memory_manager
import ../../src/nicp_cdk/storage/stable_btree

proc apiShape() =
  let manager = initMemoryManager(0)
  let users = initVirtualMemory(manager, 1'u8, limit = 1048576'u64)
  var tree = initIcStableTable[uint32, string](users.view())
  tree[1'u32] = "one"
  discard tree[1'u32]

static:
  doAssert compiles(apiShape())
