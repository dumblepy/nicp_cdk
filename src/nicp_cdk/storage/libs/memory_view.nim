## A bounded logical view over IC stable memory.
##
## Keeping the bound in this type makes accidental reads into another
## structure fail before they reach the ic0 API.

when not defined(nicpMemoryViewOnly):
  import ./stable_memory

when defined(nicpMemoryViewOnly):
  proc rawStableSize(): uint64 = 0
  proc rawStableReadInto(dst: var openArray[byte], offset: uint64) =
    discard dst; discard offset
    raise newException(ValueError, "RawMemoryView is unavailable in memory-view-only builds")
  proc rawStableWrite(offset: uint64, data: openArray[byte]) =
    discard offset; discard data
    raise newException(ValueError, "RawMemoryView is unavailable in memory-view-only builds")
else:
  proc rawStableSize(): uint64 = stableSizeBytes()
  proc rawStableReadInto(dst: var openArray[byte], offset: uint64) = stableReadInto(dst, offset)
  proc rawStableWrite(offset: uint64, data: openArray[byte]) = stableWrite(offset, data)

type StableMemoryView* = object
  baseOffset*: uint64
  limit*: uint64 # 0 means the view may grow without an explicit limit.
  sizeProc: proc(): uint64 {.closure.}
  readProc: proc(offset, size: uint64): seq[byte] {.closure.}
  writeProc: proc(offset: uint64, data: seq[byte]) {.closure.}

proc initRawMemoryView*(baseOffset: uint64 = 0, limit: uint64 = 0): StableMemoryView =
  StableMemoryView(baseOffset: baseOffset, limit: limit)

proc initMemoryView*(sizeProc: proc(): uint64 {.closure.},
                     readProc: proc(offset, size: uint64): seq[byte] {.closure.},
                     writeProc: proc(offset: uint64, data: seq[byte]) {.closure.},
                     limit: uint64 = 0): StableMemoryView =
  ## Test/alternate backend constructor.  Offsets are relative to this view.
  StableMemoryView(limit: limit, sizeProc: sizeProc, readProc: readProc, writeProc: writeProc)

proc checkRange(view: StableMemoryView, offset, size: uint64) =
  if offset > high(uint64) - size:
    raise newException(ValueError, "stable memory address overflow")
  if view.limit != 0 and (offset > view.limit or size > view.limit - offset):
    raise newException(ValueError, "stable memory view bounds exceeded")

proc readInto*(view: StableMemoryView, dst: var openArray[byte], offset: uint64) =
  view.checkRange(offset, uint64(dst.len))
  if not view.readProc.isNil:
    let data = view.readProc(offset, uint64(dst.len))
    if data.len != dst.len: raise newException(ValueError, "memory backend returned an invalid read length")
    for i in 0 ..< dst.len: dst[i] = data[i]
    return
  rawStableReadInto(dst, view.baseOffset + offset)

proc read*(view: StableMemoryView, offset, size: uint64): seq[byte] =
  view.checkRange(offset, size)
  var available = if view.sizeProc.isNil: rawStableSize() else: view.sizeProc()
  if view.sizeProc.isNil:
    if available <= view.baseOffset: available = 0 else: available -= view.baseOffset
  if view.limit != 0 and available > view.limit: available = view.limit
  if offset > available or size > available - offset:
    raise newException(ValueError, "stable memory read exceeds allocated size")
  if not view.readProc.isNil:
    result = view.readProc(offset, size)
    if result.len != int(size): raise newException(ValueError, "memory backend returned an invalid read length")
  else:
    result = newSeq[byte](int(size))
    rawStableReadInto(result, view.baseOffset + offset)

proc write*(view: StableMemoryView, offset: uint64, data: openArray[byte]) =
  view.checkRange(offset, uint64(data.len))
  if not view.writeProc.isNil:
    view.writeProc(offset, @data)
  else:
    rawStableWrite(view.baseOffset + offset, data)

proc size*(view: StableMemoryView): uint64 =
  let physical = if view.sizeProc.isNil: rawStableSize() else: view.sizeProc()
  if not view.sizeProc.isNil:
    result = physical
    if view.limit != 0 and result > view.limit: result = view.limit
    return
  if physical <= view.baseOffset: return 0
  result = physical - view.baseOffset
  if view.limit != 0 and result > view.limit: result = view.limit
