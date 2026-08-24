import ../../ic0/ic0

const StablePageSize* = 65536'u64

proc stableSizePages*(): uint64 =
  ic0_stable64_size()

proc stableSizeBytes*(): uint64 =
  stableSizePages() * StablePageSize

proc ensureStableSize*(minBytes: uint64) =
  let currentBytes = stableSizeBytes()
  if minBytes <= currentBytes:
    return
  let requiredPages = (minBytes + StablePageSize - 1) div StablePageSize
  let currentPages = stableSizePages()
  if requiredPages > currentPages:
    discard ic0_stable64_grow(requiredPages - currentPages)

proc stableWrite*(offset: uint64, data: openArray[byte]) =
  if data.len == 0:
    return
  ensureStableSize(offset + uint64(data.len))
  ic0_stable64_write(offset, cast[uint64](unsafeAddr data[0]), uint64(data.len))

proc stableRead*(offset: uint64, size: uint64): seq[byte] =
  result = newSeq[byte](int(size))
  if size == 0:
    return
  ic0_stable64_read(cast[uint64](addr result[0]), offset, size)

proc stableReadInto*(dst: var openArray[byte], offset: uint64) =
  if dst.len == 0:
    return
  ic0_stable64_read(cast[uint64](unsafeAddr dst[0]), offset, uint64(dst.len))
