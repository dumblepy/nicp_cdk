import std/endians

import ./libs/serialization
import ./libs/stable_memory

const
  SeqMagic = [byte('S'), byte('S'), byte('E'), byte('Q')]
  SeqVersion = 1'u32
  SeqHeaderSize = 32'u64

type IcStableSeq*[T] = object
  baseOffset: uint64
  length: uint64
  dataEnd: uint64
  offsets: seq[uint64]
  lengths: seq[uint32]

proc dataStart(s: IcStableSeq): uint64 =
  s.baseOffset + SeqHeaderSize

proc writeHeader[T](s: IcStableSeq[T]) =
  var header = newSeq[byte](int(SeqHeaderSize))
  header[0] = SeqMagic[0]
  header[1] = SeqMagic[1]
  header[2] = SeqMagic[2]
  header[3] = SeqMagic[3]
  var offset = 4
  var version = SeqVersion
  littleEndian32(addr header[offset], addr version)
  offset += 4
  var length = s.length
  littleEndian64(addr header[offset], addr length)
  offset += 8
  var dataEnd = s.dataEnd
  littleEndian64(addr header[offset], addr dataEnd)
  stableWrite(s.baseOffset, header)

proc readHeader[T](s: var IcStableSeq[T]): bool =
  if stableSizeBytes() < s.baseOffset + SeqHeaderSize:
    return false
  let header = stableRead(s.baseOffset, SeqHeaderSize)
  if header.len < int(SeqHeaderSize):
    return false
  if header[0] != SeqMagic[0] or header[1] != SeqMagic[1] or
     header[2] != SeqMagic[2] or header[3] != SeqMagic[3]:
    return false
  var offset = 4
  let version = deserialize[uint32](header, offset)
  if version != SeqVersion:
    return false
  s.length = deserialize[uint64](header, offset)
  s.dataEnd = deserialize[uint64](header, offset)
  let minStart = dataStart(s)
  if s.dataEnd < minStart:
    s.dataEnd = minStart
  let maxEnd = stableSizeBytes()
  if s.dataEnd > maxEnd:
    s.dataEnd = maxEnd
  result = true

proc rebuildIndex[T](s: var IcStableSeq[T]) =
  s.offsets.setLen(0)
  s.lengths.setLen(0)
  let minStart = dataStart(s)
  var offset = minStart
  let maxEnd = s.dataEnd
  var count = 0'u64
  while count < s.length and offset + 4'u64 <= maxEnd:
    let lenBytes = stableRead(offset, 4)
    var lenOffset = 0
    let elemLen = deserialize[uint32](lenBytes, lenOffset)
    let entrySize = 4'u64 + uint64(elemLen)
    if offset + entrySize > maxEnd:
      break
    s.offsets.add(offset)
    s.lengths.add(elemLen)
    offset += entrySize
    count += 1
  s.length = count
  s.dataEnd = offset
  writeHeader(s)

proc initIcStableSeq*[T](baseOffset: uint64 = 0): IcStableSeq[T] =
  result.baseOffset = baseOffset
  if not readHeader(result):
    result.length = 0
    result.dataEnd = dataStart(result)
    writeHeader(result)
  rebuildIndex(result)

proc len*[T](s: IcStableSeq[T]): int =
  int(s.length)

proc clear*[T](s: var IcStableSeq[T]) =
  s.length = 0
  s.dataEnd = dataStart(s)
  s.offsets.setLen(0)
  s.lengths.setLen(0)
  writeHeader(s)

proc `[]`*[T](s: IcStableSeq[T], idx: int): T =
  if idx < 0 or idx >= int(s.length):
    raise newException(IndexDefect, "index out of bounds")
  let entryOffset = s.offsets[idx]
  let elemLen = s.lengths[idx]
  let valueOffset = entryOffset + 4'u64
  let valueBytes = stableRead(valueOffset, uint64(elemLen))
  var valuePos = 0
  result = deserialize[T](valueBytes, valuePos)

proc `[]=`*[T](s: var IcStableSeq[T], idx: int, value: T) =
  if idx < 0 or idx >= int(s.length):
    raise newException(IndexDefect, "index out of bounds")
  let valueBytes = serialize(value)
  let newLen = uint32(valueBytes.len)
  let entryOffset = s.offsets[idx]
  let oldLen = s.lengths[idx]
  let oldEntrySize = 4'u64 + uint64(oldLen)
  let newEntrySize = 4'u64 + uint64(newLen)
  let tailStart = entryOffset + oldEntrySize
  let tailSize = s.dataEnd - tailStart
  var tailBytes: seq[byte] = @[]
  if tailSize > 0:
    tailBytes = stableRead(tailStart, tailSize)
  let lenBytes = serialize(newLen)
  stableWrite(entryOffset, lenBytes)
  stableWrite(entryOffset + 4'u64, valueBytes)
  let newTailStart = entryOffset + newEntrySize
  if tailSize > 0:
    stableWrite(newTailStart, tailBytes)
  let delta = int64(newEntrySize) - int64(oldEntrySize)
  if delta != 0:
    for i in (idx + 1) ..< s.offsets.len:
      s.offsets[i] = uint64(int64(s.offsets[i]) + delta)
  s.lengths[idx] = newLen
  s.dataEnd = uint64(int64(s.dataEnd) + delta)
  writeHeader(s)

proc add*[T](s: var IcStableSeq[T], value: T) =
  let valueBytes = serialize(value)
  let valueLen = uint32(valueBytes.len)
  let entryOffset = s.dataEnd
  let lenBytes = serialize(valueLen)
  stableWrite(entryOffset, lenBytes)
  stableWrite(entryOffset + 4'u64, valueBytes)
  s.offsets.add(entryOffset)
  s.lengths.add(valueLen)
  s.length += 1
  s.dataEnd = entryOffset + 4'u64 + uint64(valueLen)
  writeHeader(s)

proc delete*[T](s: var IcStableSeq[T], idx: int) =
  if idx < 0 or idx >= int(s.length):
    raise newException(IndexDefect, "index out of bounds")
  let entryOffset = s.offsets[idx]
  let elemLen = s.lengths[idx]
  let entrySize = 4'u64 + uint64(elemLen)
  let tailStart = entryOffset + entrySize
  let tailSize = s.dataEnd - tailStart
  if tailSize > 0:
    let tailBytes = stableRead(tailStart, tailSize)
    stableWrite(entryOffset, tailBytes)
  let delta = -int64(entrySize)
  for i in (idx + 1) ..< s.offsets.len:
    s.offsets[i] = uint64(int64(s.offsets[i]) + delta)
  s.offsets.delete(idx)
  s.lengths.delete(idx)
  s.length -= 1
  s.dataEnd = uint64(int64(s.dataEnd) + delta)
  writeHeader(s)

iterator items*[T](s: IcStableSeq[T]): T =
  for idx in 0 ..< int(s.length):
    yield s[idx]

proc toSeq*[T](s: IcStableSeq[T]): seq[T] =
  ## Collect all elements into a standard Nim seq
  result = newSeq[T](int(s.length))
  for idx in 0 ..< int(s.length):
    result[idx] = s[idx]
  # `s[idx]` reads each entry, so this is O(n) with repeated stable reads
