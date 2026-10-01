## Stable-memory abstraction. All offsets and sizes are byte based, while the
## growth unit is a stable page (64 KiB).
##
## `StableBackend` is the single generic byte-storage interface that the EOP
## storage layer (MemoryManager, IcStableTable, IcStableSeq, IcStableHashMap,
## StableValue) is built on. Concrete backends are:
##
## - `IcStableBackend`: the IC `stable64_*` syscalls (wasm32 only).
## - `VecStableBackend`: an in-memory `seq[byte]` used by native unit tests.
## - `OffsetStableBackend`: a bounded page-aligned subregion of another backend.

const StablePageSize* = 64'u64 * 1024'u64

type
  StableBackend* = ref object of RootObj

method sizePages*(backend: StableBackend): uint64 {.base.} =
  raise newException(CatchableError, "StableBackend.sizePages is not implemented")

method grow*(backend: StableBackend; pages: uint64): bool {.base.} =
  raise newException(CatchableError, "StableBackend.grow is not implemented")

method read*(backend: StableBackend; offset: uint64; dst: pointer; size: uint64) {.base.} =
  raise newException(CatchableError, "StableBackend.read is not implemented")

method write*(backend: StableBackend; offset: uint64; src: pointer; size: uint64) {.base.} =
  raise newException(CatchableError, "StableBackend.write is not implemented")

type StableRegion* = object
  ## A fixed prefix may be owned by another stable-memory user. A backend may
  ## own only `[baseOffset, baseOffset + maxBytes)` in this representation.
  baseOffset*: uint64
  maxBytes*: uint64

type OffsetStableBackend* = ref object of StableBackend
  raw: StableBackend
  baseOffset: uint64
  maxBytes: uint64

proc newOffsetStableBackend*(raw: StableBackend; baseOffset: uint64;
                             maxBytes = high(uint64)): OffsetStableBackend =
  if raw.isNil: raise newException(ValueError, "nil raw stable backend")
  if baseOffset mod StablePageSize != 0:
    raise newException(ValueError, "stable region offset must be page aligned")
  if maxBytes != high(uint64) and maxBytes mod StablePageSize != 0:
    raise newException(ValueError, "stable region size must be page aligned")
  OffsetStableBackend(raw: raw, baseOffset: baseOffset, maxBytes: maxBytes)

proc newRegionStableBackend*(raw: StableBackend; region: StableRegion): OffsetStableBackend =
  newOffsetStableBackend(raw, region.baseOffset, region.maxBytes)

proc isInRegion(backend: OffsetStableBackend; offset, size: uint64): bool {.inline.} =
  offset <= backend.maxBytes and size <= backend.maxBytes - offset

method sizePages*(backend: OffsetStableBackend): uint64 =
  let basePages = backend.baseOffset div StablePageSize
  let physicalPages = backend.raw.sizePages
  if physicalPages <= basePages: return 0
  min(physicalPages - basePages, backend.maxBytes div StablePageSize)

method grow*(backend: OffsetStableBackend; pages: uint64): bool =
  let existingPages = backend.sizePages
  if pages > (backend.maxBytes div StablePageSize) - existingPages:
    return false
  let basePages = backend.baseOffset div StablePageSize
  let physicalPages = backend.raw.sizePages
  if physicalPages < basePages and not backend.raw.grow(basePages - physicalPages):
    return false
  backend.raw.grow(pages)

method read*(backend: OffsetStableBackend; offset: uint64; dst: pointer; size: uint64) =
  if not backend.isInRegion(offset, size) or offset > high(uint64) - backend.baseOffset:
    raise newException(ValueError, "stable region read is outside configured region")
  backend.raw.read(backend.baseOffset + offset, dst, size)

method write*(backend: OffsetStableBackend; offset: uint64; src: pointer; size: uint64) =
  if not backend.isInRegion(offset, size) or offset > high(uint64) - backend.baseOffset:
    raise newException(ValueError, "stable region write is outside configured region")
  backend.raw.write(backend.baseOffset + offset, src, size)

type VecStableBackend* = ref object of StableBackend
  bytes: seq[byte]

proc newVecStableBackend*(): VecStableBackend =
  VecStableBackend(bytes: @[])

proc byteLen(backend: VecStableBackend): uint64 {.inline.} =
  uint64(backend.bytes.len)

proc inRange(backend: VecStableBackend; offset, size: uint64): bool {.inline.} =
  offset <= backend.byteLen and size <= backend.byteLen - offset

method sizePages*(backend: VecStableBackend): uint64 =
  uint64(backend.bytes.len) div StablePageSize

method grow*(backend: VecStableBackend; pages: uint64): bool =
  if pages == 0:
    return true
  if pages > uint64(high(int)) div StablePageSize:
    return false
  let extra = pages * StablePageSize
  if extra > uint64(high(int)) - backend.byteLen:
    return false
  let oldLen = backend.bytes.len
  backend.bytes.setLen(oldLen + int(extra))
  true

method read*(backend: VecStableBackend; offset: uint64; dst: pointer; size: uint64) =
  if size == 0:
    return
  if dst.isNil or not backend.inRange(offset, size):
    raise newException(ValueError, "stable read is outside allocated pages")
  copyMem(dst, unsafeAddr backend.bytes[int(offset)], int(size))

method write*(backend: VecStableBackend; offset: uint64; src: pointer; size: uint64) =
  if size == 0:
    return
  if src.isNil or not backend.inRange(offset, size):
    raise newException(ValueError, "stable write is outside allocated pages")
  copyMem(addr backend.bytes[int(offset)], src, int(size))
