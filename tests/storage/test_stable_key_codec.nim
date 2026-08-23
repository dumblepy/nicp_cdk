discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

import std/unittest
import ../../src/nicp_cdk/storage/stable_key_codec

proc compareBytes(a, b: openArray[byte]): int =
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]: return if a[i] < b[i]: -1 else: 1
  system.cmp(a.len, b.len)

suite "stable key codec":
  test "signed integer encoding preserves numeric order":
    let values = @[-32768'i16, -2'i16, -1'i16, 0'i16, 1'i16, 255'i16, 32767'i16]
    for i in 0 ..< values.high:
      check compareBytes(stableKeyEncode(values[i]), stableKeyEncode(values[i + 1])) < 0

  test "unsigned integer encoding is big endian and reversible":
    let values = @[0'u32, 1'u32, 255'u32, 256'u32, high(uint32)]
    for i, value in values:
      check stableKeyDecode[uint32](stableKeyEncode(value)) == value
      if i > 0:
        check compareBytes(stableKeyEncode(values[i - 1]), stableKeyEncode(value)) < 0

  test "strings have no length prefix in their ordering key":
    check stableKeyEncode("z") == @[byte('z')]
    check compareBytes(stableKeyEncode("a-long-key"), stableKeyEncode("b")) < 0
    check stableKeyDecode[string](stableKeyEncode("日本語")) == "日本語"
