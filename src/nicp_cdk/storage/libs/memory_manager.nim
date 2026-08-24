## Persistent bucket-based virtual memory manager for stable memory.
## Each virtual memory owns a linked list of fixed-size physical buckets, so
## independently growing structures cannot overwrite one another.

import std/endians
import ./stable_memory
import ./memory_view

const
  MemoryManagerMagic = [byte('V'), byte('M'), byte('M'), byte('2')]
  MemoryManagerVersion* = 1'u32
  MaxVirtualMemories* = 255
  ManagerHeaderSize = 8192'u64
  DescriptorSize = 24'u64
  DescriptorStart = 32'u64
  BucketHeaderSize = 8'u64
  DefaultBucketSize* = 65536'u32

type
  VirtualDescriptor = object
    head, tail, size: uint64
  MemoryManager* = ref object
    baseOffset: uint64
    bucketSize: uint32
    nextPhysical: uint64
    descriptors: array[MaxVirtualMemories, VirtualDescriptor]
  VirtualMemory* = object
    manager: MemoryManager
    memoryId*: uint8
    limit*: uint64

proc put32(data: var openArray[byte], at: int, value: uint32) =
  var le = value; littleEndian32(addr data[at], addr le)
proc put64(data: var openArray[byte], at: int, value: uint64) =
  var le = value; littleEndian64(addr data[at], addr le)
proc get32(data: openArray[byte], at: int): uint32 =
  littleEndian32(addr result, unsafeAddr data[at])
proc get64(data: openArray[byte], at: int): uint64 =
  littleEndian64(addr result, unsafeAddr data[at])

proc writeManagerHeader(manager: MemoryManager) =
  var data = newSeq[byte](int(ManagerHeaderSize))
  for i in 0 .. 3: data[i] = MemoryManagerMagic[i]
  data.put32(4, MemoryManagerVersion); data.put32(8, manager.bucketSize); data.put64(16, manager.nextPhysical)
  for index in 0 ..< MaxVirtualMemories:
    let offset = int(DescriptorStart + uint64(index) * DescriptorSize)
    data.put64(offset, manager.descriptors[index].head)
    data.put64(offset + 8, manager.descriptors[index].tail)
    data.put64(offset + 16, manager.descriptors[index].size)
  stableWrite(manager.baseOffset, data)

proc initMemoryManager*(baseOffset: uint64, bucketSize: uint32 = DefaultBucketSize): MemoryManager =
  if bucketSize <= uint32(BucketHeaderSize) or bucketSize mod StablePageSize.uint32 != 0:
    raise newException(ValueError, "bucketSize must be a stable-memory page multiple")
  new(result); result.baseOffset = baseOffset
  if stableSizeBytes() >= baseOffset + ManagerHeaderSize:
    let data = stableRead(baseOffset, ManagerHeaderSize)
    var valid = true
    for i in 0 .. 3: valid = valid and data[i] == MemoryManagerMagic[i]
    if valid:
      if data.get32(4) != MemoryManagerVersion: raise newException(ValueError, "unsupported virtual memory layout")
      result.bucketSize = data.get32(8)
      if result.bucketSize != bucketSize: raise newException(ValueError, "virtual memory bucket size mismatch")
      result.nextPhysical = data.get64(16)
      if result.nextPhysical < baseOffset + ManagerHeaderSize or result.nextPhysical > stableSizeBytes():
        raise newException(ValueError, "invalid virtual memory allocator metadata")
      for index in 0 ..< MaxVirtualMemories:
        let offset = int(DescriptorStart + uint64(index) * DescriptorSize)
        result.descriptors[index] = VirtualDescriptor(head: data.get64(offset), tail: data.get64(offset + 8), size: data.get64(offset + 16))
      return
  result.bucketSize = bucketSize
  result.nextPhysical = baseOffset + ManagerHeaderSize
  result.writeManagerHeader

proc payloadSize(manager: MemoryManager): uint64 = uint64(manager.bucketSize) - BucketHeaderSize

proc appendBucket(manager: MemoryManager, descriptorIndex: int): uint64 =
  result = manager.nextPhysical
  manager.nextPhysical += uint64(manager.bucketSize)
  var header = newSeq[byte](8); header.put64(0, 0)
  stableWrite(result, header)
  if manager.descriptors[descriptorIndex].tail == 0:
    manager.descriptors[descriptorIndex].head = result
  else:
    var tailHeader = newSeq[byte](8); tailHeader.put64(0, result)
    stableWrite(manager.descriptors[descriptorIndex].tail, tailHeader)
  manager.descriptors[descriptorIndex].tail = result
  manager.writeManagerHeader

proc bucketAt(manager: MemoryManager, memoryId: uint8, index: uint64, create: bool): uint64 =
  let descriptorIndex = int(memoryId)
  var current = manager.descriptors[descriptorIndex].head
  if current == 0:
    if not create: raise newException(ValueError, "virtual memory bucket is missing")
    current = manager.appendBucket(descriptorIndex)
  for _ in 0 ..< index:
    let header = stableRead(current, 8)
    let next = header.get64(0)
    if next == 0:
      if not create: raise newException(ValueError, "virtual memory bucket is missing")
      current = manager.appendBucket(descriptorIndex)
    else:
      current = next
  current

proc writeVirtual(memory: VirtualMemory, offset: uint64, data: seq[byte]) =
  if data.len == 0: return
  let endOffset = offset + uint64(data.len)
  if endOffset < offset: raise newException(ValueError, "virtual memory address overflow")
  let payload = memory.manager.payloadSize
  var position = offset; var sourcePosition = 0
  while sourcePosition < data.len:
    let bucketIndex = position div payload
    let inBucket = position mod payload
    let count = min(uint64(data.len - sourcePosition), payload - inBucket)
    let bucket = memory.manager.bucketAt(memory.memoryId, bucketIndex, true)
    stableWrite(bucket + BucketHeaderSize + inBucket, data[sourcePosition ..< sourcePosition + int(count)])
    position += count; sourcePosition += int(count)
  let descriptorIndex = int(memory.memoryId)
  if endOffset > memory.manager.descriptors[descriptorIndex].size:
    memory.manager.descriptors[descriptorIndex].size = endOffset
    memory.manager.writeManagerHeader

proc readVirtual(memory: VirtualMemory, offset, size: uint64): seq[byte] =
  let descriptor = memory.manager.descriptors[int(memory.memoryId)]
  if offset > descriptor.size or size > descriptor.size - offset:
    raise newException(ValueError, "virtual memory read exceeds allocated size")
  result = newSeq[byte](int(size))
  let payload = memory.manager.payloadSize
  var position = offset; var destinationPosition = 0
  while destinationPosition < result.len:
    let bucketIndex = position div payload
    let inBucket = position mod payload
    let count = min(uint64(result.len - destinationPosition), payload - inBucket)
    let bucket = memory.manager.bucketAt(memory.memoryId, bucketIndex, false)
    let part = stableRead(bucket + BucketHeaderSize + inBucket, count)
    for i, value in part: result[destinationPosition + i] = value
    position += count; destinationPosition += int(count)

proc initVirtualMemory*(manager: MemoryManager, memoryId: uint8, limit: uint64 = 0): VirtualMemory =
  VirtualMemory(manager: manager, memoryId: memoryId, limit: limit)

proc size*(memory: VirtualMemory): uint64 = memory.manager.descriptors[int(memory.memoryId)].size

proc view*(memory: VirtualMemory): StableMemoryView =
  let captured = memory
  initMemoryView(
    proc(): uint64 = captured.size,
    proc(offset, size: uint64): seq[byte] = captured.readVirtual(offset, size),
    proc(offset: uint64, data: seq[byte]) = captured.writeVirtual(offset, data),
    captured.limit
  )
