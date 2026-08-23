## Ordered, versioned encodings for keys used by IcStableTable.

import ../ic_types/ic_principal

const
  StringKeyCodecId* = 1'u32
  BoolKeyCodecId* = 2'u32
  UintKeyCodecId* = 10'u32
  IntKeyCodecId* = 20'u32
  PrincipalKeyCodecId* = 30'u32

proc putBigEndian(value: uint16): seq[byte] =
  @[byte((value shr 8) and 0xff'u16), byte(value and 0xff'u16)]

proc putBigEndian(value: uint32): seq[byte] =
  @[byte((value shr 24) and 0xff'u32), byte((value shr 16) and 0xff'u32),
    byte((value shr 8) and 0xff'u32), byte(value and 0xff'u32)]

proc putBigEndian(value: uint64): seq[byte] =
  result = newSeq[byte](8)
  for i in 0 ..< 8:
    result[i] = byte((value shr (8 * (7 - i))) and 0xff'u64)

proc stableKeyEncode*(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for i in 0 ..< value.len:
    result[i] = byte(value[i])

proc stableKeyEncode*(value: bool): seq[byte] = @[byte(if value: 1 else: 0)]
proc stableKeyEncode*(value: uint8): seq[byte] = @[byte(value)]
proc stableKeyEncode*(value: int8): seq[byte] = @[byte(cast[uint8](value) xor 0x80'u8)]
proc stableKeyEncode*(value: uint16): seq[byte] = putBigEndian(value)
proc stableKeyEncode*(value: uint32): seq[byte] = putBigEndian(value)
proc stableKeyEncode*(value: uint64): seq[byte] = putBigEndian(value)
proc stableKeyEncode*(value: int16): seq[byte] = putBigEndian(cast[uint16](value) xor 0x8000'u16)
proc stableKeyEncode*(value: int32): seq[byte] = putBigEndian(cast[uint32](value) xor 0x80000000'u32)
proc stableKeyEncode*(value: int64): seq[byte] = putBigEndian(cast[uint64](value) xor 0x8000000000000000'u64)
proc stableKeyEncode*(value: char): seq[byte] = @[byte(value)]
proc stableKeyEncode*(value: Principal): seq[byte] = value.bytes

proc stableKeyEncode*(value: int): seq[byte] =
  when sizeof(int) == 8: stableKeyEncode(int64(value))
  else: stableKeyEncode(int32(value))
proc stableKeyEncode*(value: uint): seq[byte] =
  when sizeof(uint) == 8: stableKeyEncode(uint64(value))
  else: stableKeyEncode(uint32(value))

proc stableKeyCodecId*[T](_: typedesc[T]): uint32 =
  when T is string: StringKeyCodecId
  elif T is bool: BoolKeyCodecId
  elif T is Principal: PrincipalKeyCodecId
  elif T is SomeUnsignedInt: UintKeyCodecId + uint32(sizeof(T))
  elif T is SomeSignedInt: IntKeyCodecId + uint32(sizeof(T))
  elif T is char: UintKeyCodecId + 1'u32
  else: {.error: "IcStableTable keys require a StableKeyCodec-supported type".}

proc stableKeyDecode*[T](data: openArray[byte]): T =
  when T is string:
    result = newString(data.len)
    if data.len > 0: copyMem(addr result[0], unsafeAddr data[0], data.len)
  elif T is bool:
    if data.len != 1: raise newException(ValueError, "invalid bool key")
    result = data[0] != 0
  elif T is uint8:
    if data.len != 1: raise newException(ValueError, "invalid uint8 key")
    result = data[0]
  elif T is int8:
    if data.len != 1: raise newException(ValueError, "invalid int8 key")
    result = cast[int8](data[0] xor 0x80'u8)
  elif T is char:
    if data.len != 1: raise newException(ValueError, "invalid char key")
    result = char(data[0])
  elif T is uint16 or T is int16:
    if data.len != 2: raise newException(ValueError, "invalid 16-bit key")
    let bits = (uint16(data[0]) shl 8) or uint16(data[1])
    when T is uint16: result = bits
    else: result = cast[int16](bits xor 0x8000'u16)
  elif T is uint32 or T is int32:
    if data.len != 4: raise newException(ValueError, "invalid 32-bit key")
    var bits = 0'u32
    for value in data: bits = (bits shl 8) or uint32(value)
    when T is uint32: result = bits
    else: result = cast[int32](bits xor 0x80000000'u32)
  elif T is uint64 or T is int64:
    if data.len != 8: raise newException(ValueError, "invalid 64-bit key")
    var bits = 0'u64
    for value in data: bits = (bits shl 8) or uint64(value)
    when T is uint64: result = bits
    else: result = cast[int64](bits xor 0x8000000000000000'u64)
  elif T is int:
    when sizeof(int) == 8: result = int(stableKeyDecode[int64](data))
    else: result = int(stableKeyDecode[int32](data))
  elif T is uint:
    when sizeof(uint) == 8: result = uint(stableKeyDecode[uint64](data))
    else: result = uint(stableKeyDecode[uint32](data))
  elif T is Principal:
    result = Principal.fromBlob(@data)
  else: {.error: "IcStableTable keys require a StableKeyCodec-supported type".}
