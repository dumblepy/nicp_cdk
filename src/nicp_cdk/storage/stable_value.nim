import std/endians

import ./libs/serialization as stable_ser
import ./libs/stable_memory
import ../ic_types/ic_principal

const
  ValueMagic = [byte('S'), byte('V'), byte('A'), byte('L')]
  ValueVersion = 1'u32
  ValueHeaderSize = 16'u64

type IcStableValue*[T] = object
  baseOffset: uint64
  dataLen: uint64

proc dataStart[T](db: IcStableValue[T]): uint64 =
  db.baseOffset + ValueHeaderSize

proc writeHeader[T](db: IcStableValue[T]) =
  var header = newSeq[byte](int(ValueHeaderSize))
  header[0] = ValueMagic[0]
  header[1] = ValueMagic[1]
  header[2] = ValueMagic[2]
  header[3] = ValueMagic[3]
  var offset = 4
  var version = ValueVersion
  littleEndian32(addr header[offset], addr version)
  offset += 4
  var dataLen = db.dataLen
  littleEndian64(addr header[offset], addr dataLen)
  stableWrite(db.baseOffset, header)

proc readHeader[T](db: var IcStableValue[T]): bool =
  if stableSizeBytes() < db.baseOffset + ValueHeaderSize:
    return false
  let header = stableRead(db.baseOffset, ValueHeaderSize)
  if header.len < int(ValueHeaderSize):
    return false
  if header[0] != ValueMagic[0] or header[1] != ValueMagic[1] or
     header[2] != ValueMagic[2] or header[3] != ValueMagic[3]:
    return false
  var offset = 4
  let version = stable_ser.deserialize[uint32](header, offset)
  if version != ValueVersion:
    return false
  db.dataLen = stable_ser.deserialize[uint64](header, offset)
  let maxData = stableSizeBytes() - dataStart(db)
  if db.dataLen > maxData:
    db.dataLen = maxData
  result = true

proc initIcStableValue*[T](typ: typedesc[T], baseOffset: uint64 = 0): IcStableValue[T] =
  when not (T is SomeInteger or T is SomeFloat or T is bool or T is char or T is string or T is Principal or T is object):
    {.fatal: "IcStableValue supports only basic types, Principal, or objects".}
  result.baseOffset = baseOffset
  if not readHeader(result):
    result.dataLen = 0
    writeHeader(result)

proc serialize*[T](db: IcStableValue[T], value: T): seq[byte] =
  discard db
  result = stable_ser.serialize(value)

proc deserialize*[T](db: IcStableValue[T], data: seq[byte]): T =
  discard db
  var offset = 0
  result = stable_ser.deserialize[T](data, offset)

proc set*[T](db: var IcStableValue[T], value: T) =
  let data = db.serialize(value)
  stableWrite(dataStart(db), data)
  db.dataLen = uint64(data.len)
  writeHeader(db)

proc get*[T](db: IcStableValue[T]): T =
  if db.dataLen == 0:
    raise newException(ValueError, "value not set")
  let data = stableRead(dataStart(db), db.dataLen)
  result = db.deserialize(data)

proc hasValue*[T](db: IcStableValue[T]): bool =
  db.dataLen > 0
