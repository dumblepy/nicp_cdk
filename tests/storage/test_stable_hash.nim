discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/storage/test_stable_hash.nim

import std/unittest
import ../../src/nicp_cdk/storage/libs/stable_hash

suite "stable hash":
  test "matches the SipHash-2-4 reference vector":
    let seed = StableHashSeed(k0: 0x0706050403020100'u64,
                              k1: 0x0f0e0d0c0b0a0908'u64)
    check sipHash24(seed, @[]) == 0x726fdb47dd0e0e31'u64
    check sipHash24(seed, @[0'u8]) == 0x74f839c593dc67fd'u64

  test "seeded and deterministic":
    let data = @[byte('k'), byte('e'), byte('y')]
    check sipHash24(StableHashSeed(k0: 1, k1: 2), data) == sipHash24(StableHashSeed(k0: 1, k1: 2), data)
    check sipHash24(StableHashSeed(k0: 1, k1: 2), data) != sipHash24(StableHashSeed(k0: 2, k1: 1), data)
