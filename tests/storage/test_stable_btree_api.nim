discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/storage/test_stable_btree_api.nim

## Compile-time coverage for the public generic API.  Runtime/reopen coverage
## runs in the canister test environment because stable64 is an ic0 import.
import ../../src/nicp_cdk/storage/stable_table

proc apiShape() =
  var table = initIcStableTable[string, uint64]()
  table["one"] = 1
  discard table.hasKey("one")
  discard table["one"]
  discard table.len
  discard table.lowerBound("one")
  for key, value in table.pairs:
    discard key
    discard value
  for key, value in table.range("a", "z"):
    discard key
    discard value
  table.clear()
  var uncached = initIcStableTable[uint32, string](cacheSlots = 0)
  uncached[1'u32] = "one"
  discard uncached[1'u32]

static:
  doAssert compiles(apiShape())
