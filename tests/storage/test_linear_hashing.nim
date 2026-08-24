discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/storage/test_linear_hashing.nim

import std/unittest
import ../../src/nicp_cdk/storage/libs/linear_hashing
suite "linear hashing":
  test "one bucket is split at a time":
    var state = LinearHashState(level: 1, split: 0)
    check state.bucketCount == 2
    check state.splitBucket == 0
    state.advanceSplit; check state.level == 1 and state.split == 1 and state.bucketCount == 3
    state.advanceSplit; check state.level == 2 and state.split == 0 and state.bucketCount == 4

  test "only an already split bucket uses the next hash bit":
    let state = LinearHashState(level: 2, split: 1)
    ## 0b100 is bucket 0 before it is split, then bucket 4 afterwards.
    check state.bucketIndex(0b000'u64) == 0
    check state.bucketIndex(0b100'u64) == 4
    ## Bucket 1 has not yet been split, so bit 2 is ignored for it.
    check state.bucketIndex(0b101'u64) == 1

  test "invalid persisted state is rejected":
    expect ValueError:
      discard LinearHashState(level: 2, split: 4).bucketCount
    expect ValueError:
      discard LinearHashState(level: 33, split: 0).bucketCount
