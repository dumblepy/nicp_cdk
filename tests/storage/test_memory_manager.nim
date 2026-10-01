discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

import std/unittest
import ../../src/nicp_cdk/storage/memory_manager

proc writeBytes(backend: StableBackend, offset: uint64, data: seq[byte]) =
  if data.len > 0:
    backend.write(offset, unsafeAddr data[0], uint64(data.len))

proc readBytes(backend: StableBackend, offset: uint64, size: int): seq[byte] =
  result = newSeq[byte](size)
  if size > 0:
    backend.read(offset, addr result[0], uint64(size))

proc leU64(value: uint64): array[8, byte] =
  for index in 0 ..< 8:
    result[index] = byte((value shr (index * 8)) and 0xff)

suite "memory manager":
  test "MemoryId rejects 255 and round-trips":
    check memoryIdValue(newMemoryId(0)) == 0'u8
    check memoryIdValue(newMemoryId(254)) == 254'u8
    expect ValueError:
      discard newMemoryId(255)

  test "createMemoryManagerStrict writes a valid MGR header":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw)
    check raw.sizePages >= 1
    check allocatedBucketCount(manager) == 0
    check bucketSizeInPages(manager) == DefaultBucketSizeInPages

    var magic: array[3, byte]
    raw.read(0, addr magic[0], 3)
    check magic == MemoryManagerMagic

    ## a non-empty backing store must never be treated as fresh
    expect ValueError:
      discard createMemoryManagerStrict(raw)

  test "openExistingMemoryManagerStrict round-trips a created region":
    let raw = newVecStableBackend()
    discard createMemoryManagerStrict(raw)
    let reopened = openExistingMemoryManagerStrict(raw)
    check bucketSizeInPages(reopened) == DefaultBucketSizeInPages
    check allocatedBucketCount(reopened) == 0

  test "openStableMemoryManager keeps create/open modes explicit":
    let raw = newVecStableBackend()
    let created = openStableMemoryManager(raw, smCreate)
    check bucketSizeInPages(created) == DefaultBucketSizeInPages
    let opened = openStableMemoryManager(raw, smOpenExisting)
    check allocatedBucketCount(opened) == 0
    expect ValueError:
      discard openStableMemoryManager(newVecStableBackend(), smOpenExisting)

  test "openExistingMemoryManagerStrict rejects invalid regions":
    expect ValueError:
      discard openExistingMemoryManagerStrict(newVecStableBackend())

    block:
      ## wrong magic
      let raw = newVecStableBackend()
      check raw.grow(2)
      var bad = [byte('X'), byte('X'), byte('X')]
      raw.write(0, addr bad[0], 3)
      expect ValueError:
        discard openExistingMemoryManagerStrict(raw)

    block:
      ## zero bucket size
      let raw = newVecStableBackend()
      discard createMemoryManagerStrict(raw)
      var zero = [0'u8, 0'u8]
      raw.write(6, addr zero[0], 2)
      expect ValueError:
        discard openExistingMemoryManagerStrict(raw)

    block:
      ## free marker inside the allocated range
      let raw = newVecStableBackend()
      let manager = createMemoryManagerStrict(raw)
      check manager.getMemory(newMemoryId(1)).grow(1)
      var free = [UnallocatedBucketMarker]
      raw.write(uint64(MemoryManagerHeaderBytes), addr free[0], 1)
      expect ValueError:
        discard openExistingMemoryManagerStrict(raw)

    block:
      ## non-free owner outside the allocated range
      let raw = newVecStableBackend()
      let manager = createMemoryManagerStrict(raw)
      check manager.getMemory(newMemoryId(1)).grow(1)
      var owner = [5'u8]
      raw.write(uint64(MemoryManagerHeaderBytes) + allocatedBucketCount(manager),
        addr owner[0], 1)
      expect ValueError:
        discard openExistingMemoryManagerStrict(raw)

    block:
      ## memory size does not match the allocation table
      let raw = newVecStableBackend()
      let manager = createMemoryManagerStrict(raw, bucketSizeInPages = 1)
      check manager.getMemory(newMemoryId(3)).grow(1)
      let headerOffset = 3 + 1 + 2 + 2 + 32 + 3 * 8
      var bigger = leU64(2)
      raw.write(uint64(headerOffset), addr bigger[0], 8)
      expect ValueError:
        discard openExistingMemoryManagerStrict(raw)

    block:
      ## backing store truncated below the allocated buckets
      let raw = newVecStableBackend()
      let manager = createMemoryManagerStrict(raw, bucketSizeInPages = 1)
      check manager.getMemory(newMemoryId(4)).grow(3)
      let truncated = newOffsetStableBackend(raw, 0, 2 * StablePageSize)
      expect ValueError:
        discard openExistingMemoryManagerStrict(truncated)

  test "multiple MemoryIds are isolated and survive reopen":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw, bucketSizeInPages = 1)
    let a = manager.getMemory(newMemoryId(10))
    let b = manager.getMemory(newMemoryId(11))
    check a.grow(2)
    check b.grow(3)
    check a.sizePages == 2
    check b.sizePages == 3

    let aData: seq[byte] = @[1'u8, 2, 3, 4, 5]
    let bData: seq[byte] = @[9'u8, 9, 9, 9, 9]
    writeBytes(a, 0, aData)
    writeBytes(b, 0, bData)

    var crossing = newSeq[byte](200)
    for index in 0 ..< crossing.len:
      crossing[index] = byte(index and 0xff)
    writeBytes(a, StablePageSize - 100, crossing)

    check readBytes(a, 0, aData.len) == aData
    check readBytes(b, 0, bData.len) == bData
    check readBytes(a, StablePageSize - 100, crossing.len) == crossing
    check readBytes(b, 0, aData.len) != aData

    let reopened = openExistingMemoryManagerStrict(raw)
    let a2 = reopened.getMemory(newMemoryId(10))
    let b2 = reopened.getMemory(newMemoryId(11))
    check a2.sizePages == 2
    check b2.sizePages == 3
    check readBytes(a2, 0, aData.len) == aData
    check readBytes(b2, 0, bData.len) == bData
    check readBytes(a2, StablePageSize - 100, crossing.len) == crossing

  test "opens a hand-built MGR image byte-compatibly":
    ## This fixture is written in the exact `ic-stable-structures` 0.7 layout
    ## that `nim-ic-sqlite` persists, so it also covers the "foreign fixture is
    ## reopened by nicp_cdk" direction of the format compatibility test.
    let raw = newVecStableBackend()
    check raw.grow(3) # page 0 header + one 2-page bucket

    var header = newSeq[byte](MemoryManagerHeaderBytes)
    header[0] = byte('M'); header[1] = byte('G'); header[2] = byte('R')
    header[3] = MemoryManagerLayoutVersion
    ## allocatedBuckets = 1
    header[4] = 1'u8
    ## bucketSizeInPages = 2
    header[6] = 2'u8
    ## memorySizesInPages[7] = 2 pages
    let sizeOffset = 40 + 7 * 8
    header[sizeOffset] = 2'u8
    raw.write(0, addr header[0], uint64(header.len))

    var allocations = newSeq[byte](int(MaxNumBuckets))
    for index in 0 ..< allocations.len:
      allocations[index] = UnallocatedBucketMarker
    allocations[0] = 7'u8
    raw.write(uint64(MemoryManagerHeaderBytes), addr allocations[0],
      uint64(allocations.len))

    let marker: seq[byte] = @[0xAB'u8, 0xCD, 0xEF]
    raw.write(StablePageSize, unsafeAddr marker[0], uint64(marker.len))

    let manager = openExistingMemoryManagerStrict(raw)
    check memorySizePages(manager, newMemoryId(7)) == 2
    check memoryBucketCount(manager, newMemoryId(7)) == 1
    let memory = manager.getMemory(newMemoryId(7))
    check memory.sizePages == 2
    check readBytes(memory, 0, marker.len) == marker

  test "newIcOffsetBackend partitions after the IC reserved prefix":
    ## Simulate the IC WASI reservation and check that an application manager
    ## placed after it never writes into the reserved pages.
    let raw = newVecStableBackend()
    check raw.grow(IcReservedStablePages)
    let backend = newIcOffsetBackend(raw)
    check backend.sizePages == 0

    let manager = createMemoryManagerStrict(backend)
    let memory = manager.getMemory(newMemoryId(60))
    check memory.grow(1)
    check memory.sizePages == 1
    check raw.sizePages > IcReservedStablePages

    var reserved: array[3, byte]
    raw.read(0, addr reserved[0], 3)
    check reserved == [0'u8, 0, 0]

  test "VirtualStableBackend rejects out-of-bounds access":
    let raw = newVecStableBackend()
    let manager = createMemoryManagerStrict(raw)
    let memory = manager.getMemory(newMemoryId(20))
    expect ValueError:
      let data = readBytes(memory, 0, 1)
      discard data
    check memory.grow(1)
    expect ValueError:
      let data = readBytes(memory, StablePageSize, 1)
      discard data
