## A single value stored in its own managed stable-memory region.
##
## The value and its header live at the base of a `StableMemoryView`, so a
## `StableValue` is normally constructed from a `MemoryId` handle returned by
## `MemoryManager.getMemory`. Direct physical offsets are no longer accepted.

import std/endians

import ./libs/serialization as stable_ser
import ./libs/memory_view
import ../ic_types/ic_principal

const
  ValueMagic = [byte('S'), byte('V'), byte('A'), byte('L')]
  ValueVersion = 1'u32
  ValueHeaderSize = 16'u64

type
  StableValue*[T] = object
    memory: StableMemoryView
    dataLen: uint64
  IcStableValue*[T] = StableValue[T]

proc dataStart[T](db: StableValue[T]): uint64 =
  ValueHeaderSize

proc writeHeader[T](db: StableValue[T]) =
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
  db.memory.write(0, header)

proc readHeader[T](db: var StableValue[T]): bool =
  if db.memory.size < ValueHeaderSize:
    return false
  let header = db.memory.read(0, ValueHeaderSize)
  if header.len < int(ValueHeaderSize):
    return false
  if header[0] != ValueMagic[0] or header[1] != ValueMagic[1] or
     header[2] != ValueMagic[2] or header[3] != ValueMagic[3]:
    return false
  var offset = 4
  let version = stable_ser.deserialize[uint32](header, offset)
  if version != ValueVersion:
    raise newException(ValueError, "unsupported SVAL layout version")
  db.dataLen = stable_ser.deserialize[uint64](header, offset)
  let available = db.memory.size - ValueHeaderSize
  if db.dataLen > available:
    raise newException(ValueError, "invalid SVAL metadata")
  result = true

proc initStableValue*[T](memory: StableMemoryView): StableValue[T] =
  when not (T is SomeInteger or T is SomeFloat or T is bool or T is char or T is string or T is Principal or T is object):
    {.fatal: "StableValue supports only basic types, Principal, or objects".}
  result.memory = memory
  if not readHeader(result):
    result.dataLen = 0
    writeHeader(result)

proc initStableValue*[T](backend: StableBackend): StableValue[T] =
  ## Convenience overload: a `StableBackend` (for example a virtual memory from
  ## `MemoryManager.getMemory`) is adapted through `view()`.
  initStableValue[T](backend.view())

proc initIcStableValue*[T](memory: StableMemoryView): IcStableValue[T] =
  initStableValue[T](memory)

proc initIcStableValue*[T](backend: StableBackend): IcStableValue[T] =
  initStableValue[T](backend)

proc serialize*[T](db: StableValue[T], value: T): seq[byte] =
  discard db
  result = stable_ser.serialize(value)

proc deserialize*[T](db: StableValue[T], data: seq[byte]): T =
  discard db
  var offset = 0
  result = stable_ser.deserialize[T](data, offset)

proc set*[T](db: var StableValue[T], value: T) =
  let data = db.serialize(value)
  db.memory.write(dataStart(db), data)
  db.dataLen = uint64(data.len)
  writeHeader(db)

proc get*[T](db: StableValue[T]): T =
  if db.dataLen == 0:
    raise newException(ValueError, "value not set")
  let data = db.memory.read(dataStart(db), db.dataLen)
  result = db.deserialize(data)

proc hasValue*[T](db: StableValue[T]): bool =
  db.dataLen > 0
