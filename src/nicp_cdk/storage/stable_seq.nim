## Stable-memory-native sequence.
##
## Only the fixed-size header is loaded when the sequence is opened. Element
## offsets are deliberately not cached on the heap; operations locate entries
## directly in stable memory.

import std/endians

import ./libs/serialization
import ./libs/memory_view

export memory_view

const
  SeqMagic = [byte('S'), byte('S'), byte('E'), byte('Q')]
  SeqVersion = 2'u32
  SeqHeaderSize = 32'u64
  CopyBufferSize = 4096'u64

type IcStableSeq*[T] = object
  memory: StableMemoryView
  length: uint64
  dataEnd: uint64

proc dataStart[T](s: IcStableSeq[T]): uint64 = SeqHeaderSize

proc writeHeader[T](s: IcStableSeq[T]) =
  var header = newSeq[byte](int(SeqHeaderSize))
  for index in 0 .. 3: header[index] = SeqMagic[index]
  var version = SeqVersion
  var length = s.length
  var dataEnd = s.dataEnd
  littleEndian32(addr header[4], addr version)
  littleEndian64(addr header[8], addr length)
  littleEndian64(addr header[16], addr dataEnd)
  s.memory.write(0, header)

proc readHeader[T](s: var IcStableSeq[T]): bool =
  if s.memory.size < SeqHeaderSize:
    return false
  let header = s.memory.read(0, SeqHeaderSize)
  for index in 0 .. 3:
    if header[index] != SeqMagic[index]:
      return false
  var version: uint32
  littleEndian32(addr version, unsafeAddr header[4])
  if version != SeqVersion:
    raise newException(ValueError, "unsupported SSEQ layout version; migrate the sequence before opening it")
  littleEndian64(addr s.length, unsafeAddr header[8])
  littleEndian64(addr s.dataEnd, unsafeAddr header[16])
  if s.dataEnd < s.dataStart or s.dataEnd > s.memory.size:
    raise newException(ValueError, "invalid SSEQ metadata")
  result = true

proc readLength[T](s: IcStableSeq[T], offset: uint64): uint32 =
  if offset > s.dataEnd or s.dataEnd - offset < 4'u64:
    raise newException(ValueError, "invalid SSEQ element offset")
  var bytes: array[4, byte]
  s.memory.readInto(bytes, offset)
  littleEndian32(addr result, addr bytes[0])

proc entryAt[T](s: IcStableSeq[T], idx: int): (uint64, uint32) =
  if idx < 0 or idx >= int(s.length):
    raise newException(IndexDefect, "index out of bounds")
  var offset = s.dataStart
  for _ in 0 ..< idx:
    let valueLen = s.readLength(offset)
    let entrySize = 4'u64 + uint64(valueLen)
    if entrySize > s.dataEnd - offset:
      raise newException(ValueError, "corrupt SSEQ element length")
    offset += entrySize
  let valueLen = s.readLength(offset)
  if 4'u64 + uint64(valueLen) > s.dataEnd - offset:
    raise newException(ValueError, "corrupt SSEQ element length")
  (offset, valueLen)

proc moveRange[T](s: IcStableSeq[T], source, destination, size: uint64) =
  ## Move within stable memory with a bounded buffer. Copy backwards for an
  ## expanding replacement so overlapping data is preserved.
  if size == 0 or source == destination:
    return
  var buffer = newSeq[byte](int(min(CopyBufferSize, size)))
  if destination > source:
    var remaining = size
    while remaining > 0:
      let chunk = min(uint64(buffer.len), remaining)
      let start = remaining - chunk
      s.memory.readInto(buffer.toOpenArray(0, int(chunk) - 1), source + start)
      s.memory.write(destination + start, buffer.toOpenArray(0, int(chunk) - 1))
      remaining = start
  else:
    var moved = 0'u64
    while moved < size:
      let chunk = min(uint64(buffer.len), size - moved)
      s.memory.readInto(buffer.toOpenArray(0, int(chunk) - 1), source + moved)
      s.memory.write(destination + moved, buffer.toOpenArray(0, int(chunk) - 1))
      moved += chunk

proc initIcStableSeq*[T](memory: StableMemoryView): IcStableSeq[T] =
  result.memory = memory
  if not result.readHeader:
    result.length = 0
    result.dataEnd = result.dataStart
    result.writeHeader

proc initIcStableSeq*[T](baseOffset: uint64 = 0): IcStableSeq[T] =
  ## Compatibility overload for a raw stable-memory region.
  initIcStableSeq[T](initRawMemoryView(baseOffset))

proc len*[T](s: IcStableSeq[T]): int = int(s.length)

proc clear*[T](s: var IcStableSeq[T]) =
  s.length = 0
  s.dataEnd = s.dataStart
  s.writeHeader

proc `[]`*[T](s: IcStableSeq[T], idx: int): T =
  let (entryOffset, valueLen) = s.entryAt(idx)
  let valueBytes = s.memory.read(entryOffset + 4'u64, uint64(valueLen))
  var valuePos = 0
  deserialize[T](valueBytes, valuePos)

proc `[]=`*[T](s: var IcStableSeq[T], idx: int, value: T) =
  let (entryOffset, oldLen) = s.entryAt(idx)
  let valueBytes = serialize(value)
  if uint64(valueBytes.len) > uint64(high(uint32)):
    raise newException(ValueError, "SSEQ element is too large")
  let newLen = uint32(valueBytes.len)
  let oldEntrySize = 4'u64 + uint64(oldLen)
  let newEntrySize = 4'u64 + uint64(newLen)
  let tailStart = entryOffset + oldEntrySize
  let tailSize = s.dataEnd - tailStart
  let newTailStart = entryOffset + newEntrySize
  s.moveRange(tailStart, newTailStart, tailSize)
  var lenBytes: array[4, byte]
  var serializedLen = newLen
  littleEndian32(addr lenBytes[0], addr serializedLen)
  s.memory.write(entryOffset, lenBytes)
  s.memory.write(entryOffset + 4'u64, valueBytes)
  s.dataEnd = newTailStart + tailSize
  s.writeHeader

proc add*[T](s: var IcStableSeq[T], value: T) =
  let valueBytes = serialize(value)
  if uint64(valueBytes.len) > uint64(high(uint32)):
    raise newException(ValueError, "SSEQ element is too large")
  var lenBytes: array[4, byte]
  var valueLen = uint32(valueBytes.len)
  littleEndian32(addr lenBytes[0], addr valueLen)
  s.memory.write(s.dataEnd, lenBytes)
  s.memory.write(s.dataEnd + 4'u64, valueBytes)
  s.length += 1
  s.dataEnd += 4'u64 + uint64(valueLen)
  s.writeHeader

proc delete*[T](s: var IcStableSeq[T], idx: int) =
  let (entryOffset, valueLen) = s.entryAt(idx)
  let entrySize = 4'u64 + uint64(valueLen)
  let tailStart = entryOffset + entrySize
  let tailSize = s.dataEnd - tailStart
  s.moveRange(tailStart, entryOffset, tailSize)
  s.length -= 1
  s.dataEnd -= entrySize
  s.writeHeader

iterator items*[T](s: IcStableSeq[T]): T =
  var offset = s.dataStart
  for _ in 0'u64 ..< s.length:
    let valueLen = s.readLength(offset)
    if 4'u64 + uint64(valueLen) > s.dataEnd - offset:
      raise newException(ValueError, "corrupt SSEQ element length")
    let valueBytes = s.memory.read(offset + 4'u64, uint64(valueLen))
    var valuePos = 0
    yield deserialize[T](valueBytes, valuePos)
    offset += 4'u64 + uint64(valueLen)

proc toSeq*[T](s: IcStableSeq[T]): seq[T] =
  result = newSeq[T](int(s.length))
  var index = 0
  for value in s.items:
    result[index] = value
    inc index
