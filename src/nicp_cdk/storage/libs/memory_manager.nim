## MemoryManager: `MGR` virtual stable memory.
##
## This is a Nim port of the Rust `ic-sqlite-vfs` `stable::memory_manager` fork,
## which keeps the byte format of `ic-stable-structures` 0.7 so an existing
## `MGR` image can be loaded unchanged. A `MemoryManager` owns a raw
## `StableBackend` and hands out page-addressed virtual memories by `MemoryId`;
## any stable data structure then lives inside one virtual memory instead of
## owning the whole raw region.
##
## Physical layout (little-endian, matching the upstream manager):
##
## ```text
## page 0
##   +0     magic "MGR"                         3 bytes
##   +3     layout version                      1 byte  (= 1)
##   +4     allocated bucket count              u16
##   +6     bucket size in stable pages         u16     (default 128)
##   +8     reserved                           32 bytes
##   +40    memory size in pages per MemoryId  255 * u64
##   +2080  bucket allocation table            32768 * u8 (owner id, 255 = free)
## page 1+
##   bucket n payload = bucketSizeInPages * 64 KiB
## ```
##
## A virtual memory maps `logical offset -> bucket -> physical address`:
##
## ```text
## bucket_index = logical_offset div bucket_bytes
## in_bucket    = logical_offset mod bucket_bytes
## physical     = 64 KiB + bucket_index_of_memory * bucket_bytes + in_bucket
## ```
##
## The manager is strictly loaded: a non-empty region whose header is not a
## valid `MGR` image is rejected rather than overwritten.

import ./stable_backend

const
  MemoryManagerMagic*: array[3, byte] = [byte('M'), byte('G'), byte('R')]
  MemoryManagerLayoutVersion* = 1'u8
  MaxNumMemories* = 255'u8
  MaxNumBuckets* = 32768'u64
  UnallocatedBucketMarker* = MaxNumMemories
  DefaultBucketSizeInPages* = 128'u16
  BucketsOffsetInPages* = 1'u64
  HeaderReservedBytes = 32
  ## Header size must stay byte-identical to `ic-stable-structures` 0.7:
  ## `3 + 1 + 2 + 2 + 32 + 255 * 8` = 2080 bytes.
  MemoryManagerHeaderBytes* = 3 + 1 + 2 + 2 + HeaderReservedBytes + int(MaxNumMemories) * 8
  BucketAllocationTableBytes = int(MaxNumBuckets)

type
  MemoryId* = distinct uint8

  MemoryManager* = ref object
    backend: StableBackend
    bucketSizeInPages: uint16
    allocatedBuckets: uint16
    memorySizesInPages: array[int(MaxNumMemories), uint64]
    memoryBuckets: array[int(MaxNumMemories), seq[uint16]]

  VirtualStableBackend* = ref object of StableBackend
    manager: MemoryManager
    id: MemoryId
    ## One-entry bucket cache. It caches the virtual-to-physical translation of
    ## a single logical bucket so a request that stays inside that bucket skips
    ## the division, bucket-array lookup and splitting loop. It is per
    ## `VirtualStableBackend` instance, never shared across MemoryIds. Bucket
    ## allocation only ever appends, so an existing bucket never moves and the
    ## cache cannot go stale across `grow`.
    cacheValid: bool
    cacheLogicalBase: uint64   ## bucketIndex * bucketBytes
    cachePhysicalBase: uint64  ## bucketAddress(physical bucket)
    cacheLength: uint64        ## bucketBytes

func newMemoryId*(id: uint8): MemoryId =
  ## `255` is the unallocated bucket marker and is not a legal memory id.
  ## Declared `func` so a schema registry can spell ids as compile-time `const`.
  if id == UnallocatedBucketMarker:
    raise newException(ValueError, "memory id 255 is reserved")
  MemoryId(id)

func memoryIdValue*(id: MemoryId): uint8 {.inline.} = uint8(id)

# ---------------------------------------------------------------------------
# little-endian helpers (fixed-width, alignment independent)
# ---------------------------------------------------------------------------

proc putU16(data: var openArray[byte]; offset: int; value: uint16) =
  data[offset] = byte(value and 0xff)
  data[offset + 1] = byte(value shr 8)

proc putU64(data: var openArray[byte]; offset: int; value: uint64) =
  for index in 0 ..< 8:
    data[offset + index] = byte((value shr (index * 8)) and 0xff)

proc getU16(data: openArray[byte]; offset: int): uint16 =
  uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)

proc getU64(data: openArray[byte]; offset: int): uint64 =
  for index in 0 ..< 8:
    result = result or (uint64(data[offset + index]) shl (index * 8))

# ---------------------------------------------------------------------------
# header / allocation table persistence
# ---------------------------------------------------------------------------

proc bucketBytes(manager: MemoryManager): uint64 {.inline.} =
  uint64(manager.bucketSizeInPages) * StablePageSize

proc bucketAddress(manager: MemoryManager; bucket: uint16): uint64 {.inline.} =
  BucketsOffsetInPages * StablePageSize + manager.bucketBytes * uint64(bucket)

proc saveHeader(manager: MemoryManager) =
  var header = newSeq[byte](MemoryManagerHeaderBytes)
  for index in 0 ..< 3:
    header[index] = MemoryManagerMagic[index]
  header[3] = MemoryManagerLayoutVersion
  header.putU16(4, manager.allocatedBuckets)
  header.putU16(6, manager.bucketSizeInPages)
  var offset = 3 + 1 + 2 + 2 + HeaderReservedBytes
  for size in manager.memorySizesInPages:
    header.putU64(offset, size)
    offset += 8
  manager.backend.write(0, addr header[0], uint64(header.len))

proc initNew(backend: StableBackend; bucketSizeInPages: uint16): MemoryManager =
  if bucketSizeInPages == 0:
    raise newException(ValueError, "bucket size must be greater than zero")
  if backend.sizePages == 0 and not backend.grow(1):
    raise newException(ValueError,
      "unable to grow stable memory for the memory manager header")
  var allocations = newSeq[byte](BucketAllocationTableBytes)
  for index in 0 ..< allocations.len:
    allocations[index] = UnallocatedBucketMarker
  backend.write(uint64(MemoryManagerHeaderBytes), addr allocations[0],
    uint64(allocations.len))
  result = MemoryManager(backend: backend, bucketSizeInPages: bucketSizeInPages)
  result.saveHeader()

proc loadValidated(backend: StableBackend): MemoryManager =
  ## Loads and fully validates an existing `MGR` image. Any inconsistency
  ## raises `ValueError` before it can become in-memory state.
  var header = newSeq[byte](MemoryManagerHeaderBytes)
  backend.read(0, addr header[0], uint64(header.len))
  for index in 0 ..< 3:
    if header[index] != MemoryManagerMagic[index] or
        header[3] != MemoryManagerLayoutVersion:
      raise newException(ValueError,
        "non-empty stable memory does not contain a MemoryManager layout")
  let allocatedBuckets = header.getU16(4)
  let bucketSizeInPages = header.getU16(6)
  if uint64(allocatedBuckets) > MaxNumBuckets:
    raise newException(ValueError,
      "invalid memory manager header: allocated bucket count exceeds maximum")
  if bucketSizeInPages == 0:
    raise newException(ValueError,
      "invalid memory manager header: bucket size is zero")

  var memorySizes: array[int(MaxNumMemories), uint64]
  var offset = 3 + 1 + 2 + 2 + HeaderReservedBytes
  for index in 0 ..< int(MaxNumMemories):
    memorySizes[index] = header.getU64(offset)
    offset += 8
  for index in 0 ..< int(MaxNumMemories):
    if memorySizes[index] > high(uint64) div StablePageSize:
      raise newException(ValueError,
        "invalid memory manager header: memory size overflows bytes")

  var allocations = newSeq[byte](BucketAllocationTableBytes)
  backend.read(uint64(MemoryManagerHeaderBytes), addr allocations[0],
    uint64(allocations.len))
  var memoryBuckets: array[int(MaxNumMemories), seq[uint16]]
  for bucket in 0 ..< int(allocatedBuckets):
    let owner = allocations[bucket]
    if owner == UnallocatedBucketMarker:
      raise newException(ValueError,
        "invalid memory manager allocation table: allocated bucket has no owner")
    memoryBuckets[int(owner)].add uint16(bucket)
  for bucket in int(allocatedBuckets) ..< allocations.len:
    if allocations[bucket] != UnallocatedBucketMarker:
      raise newException(ValueError,
        "invalid memory manager allocation table: unallocated bucket has an owner")

  let bucketSize = uint64(bucketSizeInPages)
  for index in 0 ..< int(MaxNumMemories):
    let expected = (memorySizes[index] + bucketSize - 1) div bucketSize
    if expected != uint64(memoryBuckets[index].len):
      raise newException(ValueError,
        "invalid memory manager layout: memory size and bucket count mismatch")

  let requiredPages = BucketsOffsetInPages + bucketSize * uint64(allocatedBuckets)
  if backend.sizePages < requiredPages:
    raise newException(ValueError,
      "invalid memory manager layout: backing stable memory is truncated")

  result = MemoryManager(backend: backend, bucketSizeInPages: bucketSizeInPages,
    allocatedBuckets: allocatedBuckets, memorySizesInPages: memorySizes,
    memoryBuckets: memoryBuckets)

proc createMemoryManagerStrict*(backend: StableBackend;
    bucketSizeInPages = DefaultBucketSizeInPages): MemoryManager =
  ## Creates a brand-new `MGR` region and requires the raw backing store to be
  ## completely empty (`sizePages == 0`). A non-empty region is never probed,
  ## all-zeroed, or overwritten: the composition root has to guarantee that the
  ## backing memory is fresh before calling this.
  if backend.isNil:
    raise newException(ValueError, "nil stable backend")
  if backend.sizePages != 0:
    raise newException(ValueError,
      "new memory manager requires empty stable memory")
  initNew(backend, bucketSizeInPages)

proc openExistingMemoryManagerStrict*(backend: StableBackend): MemoryManager =
  ## Loads and validates an already persisted `MGR` region. A missing backing
  ## store (`sizePages == 0`), an unknown magic and any inconsistent layout are
  ## rejected without writing. `post_upgrade` must use this entry point so a
  ## wrong or empty region can never silently become a fresh manager.
  if backend.isNil:
    raise newException(ValueError, "nil stable backend")
  if backend.sizePages == 0:
    raise newException(ValueError, "existing memory manager is missing")
  loadValidated(backend)

type StableMemoryOpenMode* = enum
  smCreate
  smOpenExisting

proc openStableMemoryManager*(backend: StableBackend;
    mode: StableMemoryOpenMode): MemoryManager =
  ## Explicit lifecycle wrapper. `smCreate` is for `canister_init` and
  ## `smOpenExisting` is for `post_upgrade`; the mode is never inferred from
  ## the backing store, so a wrong region cannot be silently initialized.
  case mode
  of smCreate: createMemoryManagerStrict(backend)
  of smOpenExisting: openExistingMemoryManagerStrict(backend)

const IcReservedStablePages* = 1025'u64
  ## The IC WASI environment, when the polyfill is linked, installs its own
  ## `MGR` region at physical offset 0 and grows stable memory to one header page
  ## plus eight 128-page buckets (= 1025 pages) during instantiation. An
  ## application must place its own manager after that reserved prefix.

proc newIcOffsetBackend*(raw: StableBackend): OffsetStableBackend =
  ## Returns the application's stable backend after the IC-reserved `MGR`
  ## prefix. This is a deliberate composition, not an implicit "safe offset": it
  ## is tied to the IC layout (1025 pages) and must be re-verified whenever the
  ## WASI polyfill version or the build mode changes. A canister that does not
  ## link the polyfill can pass `newIcStableBackend()` directly.
  newOffsetStableBackend(raw, IcReservedStablePages * StablePageSize)

# ---------------------------------------------------------------------------
# virtual memory operations
# ---------------------------------------------------------------------------

proc memorySizePages*(manager: MemoryManager; id: MemoryId): uint64 =
  manager.memorySizesInPages[int(uint8(id))]

proc memoryBucketCount*(manager: MemoryManager; id: MemoryId): int =
  manager.memoryBuckets[int(uint8(id))].len

proc allocatedBucketCount*(manager: MemoryManager): uint64 =
  uint64(manager.allocatedBuckets)

proc bucketSizeInPages*(manager: MemoryManager): uint16 =
  manager.bucketSizeInPages

proc rawBackend*(manager: MemoryManager): StableBackend = manager.backend

proc assertVirtualBounds(manager: MemoryManager; id: MemoryId; offset, size: uint64) =
  let pages = manager.memorySizesInPages[int(uint8(id))]
  if pages > high(uint64) div StablePageSize:
    raise newException(ValueError, "virtual memory size overflows bytes")
  let capacity = pages * StablePageSize
  if offset > capacity or size > capacity - offset:
    raise newException(ValueError, "virtual memory access is out of bounds")

proc growMemory*(manager: MemoryManager; id: MemoryId; pages: uint64): bool =
  if pages == 0: return true
  let index = int(uint8(id))
  let oldSize = manager.memorySizesInPages[index]
  if oldSize > high(uint64) - pages: return false
  let newSize = oldSize + pages
  if newSize > high(uint64) div StablePageSize: return false
  let bucketSize = uint64(manager.bucketSizeInPages)
  let currentBuckets = (oldSize + bucketSize - 1) div bucketSize
  let requiredBuckets = (newSize + bucketSize - 1) div bucketSize
  let newBuckets = requiredBuckets - currentBuckets
  if uint64(manager.allocatedBuckets) + newBuckets > MaxNumBuckets: return false

  let targetAllocated = uint64(manager.allocatedBuckets) + newBuckets
  let pagesNeeded = BucketsOffsetInPages + bucketSize * targetAllocated
  if pagesNeeded > manager.backend.sizePages:
    if not manager.backend.grow(pagesNeeded - manager.backend.sizePages):
      return false

  ## Mark the new buckets as owned by this memory in one backing write so a
  ## failure cannot leave a partially updated allocation table behind.
  if newBuckets > 0:
    let firstBucket = uint64(manager.allocatedBuckets)
    var owners = newSeq[byte](int(newBuckets))
    for offset in 0 ..< owners.len:
      owners[offset] = uint8(id)
    manager.backend.write(uint64(MemoryManagerHeaderBytes) + firstBucket,
      addr owners[0], uint64(owners.len))
    for offset in 0 ..< owners.len:
      manager.memoryBuckets[index].add uint16(firstBucket + uint64(offset))
    manager.allocatedBuckets = uint16(targetAllocated)
  manager.memorySizesInPages[index] = newSize
  manager.saveHeader()
  true

method sizePages*(vm: VirtualStableBackend): uint64 =
  vm.manager.memorySizePages(vm.id)

method grow*(vm: VirtualStableBackend; pages: uint64): bool =
  vm.manager.growMemory(vm.id, pages)

method read*(vm: VirtualStableBackend; offset: uint64; dst: pointer; size: uint64) =
  if size == 0: return
  if dst.isNil:
    raise newException(ValueError, "nil virtual memory read buffer")
  let manager = vm.manager
  manager.assertVirtualBounds(vm.id, offset, size)
  let bucketBytes = manager.bucketBytes
  if vm.cacheValid and offset >= vm.cacheLogicalBase:
    let relative = offset - vm.cacheLogicalBase
    if relative < vm.cacheLength and size <= vm.cacheLength - relative:
      manager.backend.read(vm.cachePhysicalBase + relative, dst, size)
      return
  let buckets = manager.memoryBuckets[int(uint8(vm.id))]
  let target = cast[ptr UncheckedArray[byte]](dst)
  var logical = offset
  var remaining = size
  var written = 0'u64
  while remaining > 0:
    let bucketIndex = logical div bucketBytes
    let inBucket = logical - bucketIndex * bucketBytes
    let chunk = min(remaining, bucketBytes - inBucket)
    let physical = manager.bucketAddress(buckets[int(bucketIndex)]) + inBucket
    vm.cacheValid = true
    vm.cacheLogicalBase = bucketIndex * bucketBytes
    vm.cachePhysicalBase = physical - inBucket
    vm.cacheLength = bucketBytes
    manager.backend.read(physical, addr target[int(written)], chunk)
    written += chunk
    logical += chunk
    remaining -= chunk

method write*(vm: VirtualStableBackend; offset: uint64; src: pointer; size: uint64) =
  if size == 0: return
  if src.isNil:
    raise newException(ValueError, "nil virtual memory write buffer")
  let manager = vm.manager
  manager.assertVirtualBounds(vm.id, offset, size)
  let bucketBytes = manager.bucketBytes
  if vm.cacheValid and offset >= vm.cacheLogicalBase:
    let relative = offset - vm.cacheLogicalBase
    if relative < vm.cacheLength and size <= vm.cacheLength - relative:
      manager.backend.write(vm.cachePhysicalBase + relative, src, size)
      return
  let buckets = manager.memoryBuckets[int(uint8(vm.id))]
  let source = cast[ptr UncheckedArray[byte]](src)
  var logical = offset
  var remaining = size
  var consumed = 0'u64
  while remaining > 0:
    let bucketIndex = logical div bucketBytes
    let inBucket = logical - bucketIndex * bucketBytes
    let chunk = min(remaining, bucketBytes - inBucket)
    let physical = manager.bucketAddress(buckets[int(bucketIndex)]) + inBucket
    vm.cacheValid = true
    vm.cacheLogicalBase = bucketIndex * bucketBytes
    vm.cachePhysicalBase = physical - inBucket
    vm.cacheLength = bucketBytes
    manager.backend.write(physical, addr source[int(consumed)], chunk)
    consumed += chunk
    logical += chunk
    remaining -= chunk

proc getMemory*(manager: MemoryManager; id: MemoryId): VirtualStableBackend =
  ## Returns a `StableBackend` view of virtual memory `id`. It can be passed
  ## directly to `initIcStableTable` / `initIcStableSeq` / `initIcStableHashMap`
  ## / `initStableValue` so a structure lives inside the manager.
  VirtualStableBackend(manager: manager, id: id)
