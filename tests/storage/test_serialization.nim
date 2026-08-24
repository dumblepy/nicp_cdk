discard """
  cmd : "nim c --skipUserCfg $file"
"""
# nim c -r tests/storage/test_serialization.nim

import unittest
import std/tables
import ../../src/nicp_cdk/storage/libs/serialization
import ../../src/nicp_cdk/ic_types/ic_principal

type UserProfile = object
  id: uint32
  name: string
  active: bool


suite "storage serialization primitives":
  test "uint8":
    let value = 0xAB'u8
    let data = serialize(value)
    check data.len == 1
    check data[0] == value
    var offset = 0
    let decoded = deserialize[uint8](data, offset)
    check decoded == value
    check offset == data.len

  test "int8":
    let value = -0x12'i8
    let data = serialize(value)
    check data.len == 1
    check data[0] == byte(value)
    var offset = 0
    let decoded = deserialize[int8](data, offset)
    check decoded == value
    check offset == data.len

  test "uint16 little-endian layout":
    let value = 0x3412'u16
    let data = serialize(value)
    check data.len == 2
    check data[0] == 0x12'u8
    check data[1] == 0x34'u8
    var offset = 0
    let decoded = deserialize[uint16](data, offset)
    check decoded == value

  test "int16":
    let value = -0x1234'i16
    let data = serialize(value)
    check data.len == 2
    var offset = 0
    let decoded = deserialize[int16](data, offset)
    check decoded == value

  test "uint32 little-endian bytes":
    let value = 0xAABBCCDD'u32
    let data = serialize(value)
    check data.len == 4
    check data[0] == 0xDD'u8
    check data[3] == 0xAA'u8
    var offset = 0
    let decoded = deserialize[uint32](data, offset)
    check decoded == value

  test "int32":
    let value = -0x112233'i32
    let data = serialize(value)
    check data.len == 4
    var offset = 0
    let decoded = deserialize[int32](data, offset)
    check decoded == value

  test "uint64 layout and":
    let value = 0x1122334455667788'u64
    let data = serialize(value)
    check data.len == 8
    check data[0] == 0x88'u8
    check data[7] == 0x11'u8
    var offset = 0
    let decoded = deserialize[uint64](data, offset)
    check decoded == value

  test "int64":
    let value = -0x1122334455'i64
    let data = serialize(value)
    check data.len == 8
    var offset = 0
    let decoded = deserialize[int64](data, offset)
    check decoded == value

  test "bool serialization":
    for value in [false, true]:
      let data = serialize(value)
      check data.len == 1
      check data[0] == byte(if value: 1 else: 0)
      var offset = 0
      let decoded = deserialize[bool](data, offset)
      check decoded == value

  test "string":
    let text = "IcStable"
    let data = serialize(text)
    check data.len == 4 + text.len
    var offset = 0
    let decoded = deserialize[string](data, offset)
    check decoded == text
    check offset == data.len

  test "empty string serialization":
    let data = serialize("")
    check data.len == 4
    var offset = 0
    let decoded = deserialize[string](data, offset)
    check decoded == ""

  test "native int":
    let value = if sizeof(int) == 8: int(0x11223344) else: int(0x3344)
    let data = serialize(value)
    check data.len == sizeof(int)
    var offset = 0
    let decoded = deserialize[int](data, offset)
    check decoded == value
    check offset == data.len

  test "native uint":
    let value = if sizeof(uint) == 8: uint(0xAABBCCDD) else: uint(0xCCDD)
    let data = serialize(value)
    check data.len == sizeof(uint)
    var offset = 0
    let decoded = deserialize[uint](data, offset)
    check decoded == value
    check offset == data.len

  test "principal":
    let original = Principal.fromText("aaaaa-aa")
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[Principal](data, offset)
    check decoded.bytes == original.bytes
    check decoded.text == original.text
    check offset == data.len


suite "storage serialization composites":
  test "object":
    let original = UserProfile(id: 7'u32, name: "Alice", active: true)
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[UserProfile](data, offset)
    check decoded.id == original.id
    check decoded.name == original.name
    check decoded.active == original.active
    check offset == data.len

  test "seq with uint32":
    let original:seq[uint32] = @[1, 42, 999]
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[seq[uint32]](data, offset)
    check decoded == original
    check offset == data.len

  test "seq with principal":
    let original = @[
      Principal.fromText("aaaaa-aa"),
      Principal.fromText("2vxsx-fae")
    ]
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[seq[Principal]](data, offset)
    check decoded.len == original.len
    for i in 0 ..< original.len:
      check decoded[i].text == original[i].text
      check decoded[i].bytes == original[i].bytes
    check offset == data.len

  test "table with principal values":
    var original = initTable[string, Principal]()
    original["management"] = Principal.fromText("aaaaa-aa")
    original["anonymous"] = Principal.fromText("2vxsx-fae")
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[Table[string, Principal]](data, offset)
    check decoded.len == original.len
    for key, value in original.pairs:
      check decoded[key].text == value.text
      check decoded[key].bytes == value.bytes
    check offset == data.len

  test "table ref with principal values":
    var original = newTable[string, Principal]()
    original["governance"] = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai")
    original["anonymous"] = Principal.fromText("2vxsx-fae")
    let data = serialize(original)
    var offset = 0
    let decoded = deserialize[TableRef[string, Principal]](data, offset)
    check decoded.len == original.len
    for key, value in original.pairs:
      check decoded[key].text == value.text
      check decoded[key].bytes == value.bytes
    check offset == data.len
