## A bounded logical view over a `StableBackend`.
##
## `StableMemoryView` keeps the existing stable-structure code working while
## moving the backing store to the generic `StableBackend` abstraction. The view
## is responsible for the write-time auto-growth that the data structures rely
## on: a write past the current backend size grows the backend first. Raw
## physical offsets are no longer part of the public API.

import ./stable_backend

export stable_backend

type StableMemoryView* = object
  limit*: uint64 # 0 means the view may grow without an explicit limit.
  sizeProc: proc(): uint64 {.closure.}
  readProc: proc(offset, size: uint64): seq[byte] {.closure.}
  writeProc: proc(offset: uint64, data: seq[byte]) {.closure.}

proc initMemoryView*(sizeProc: proc(): uint64 {.closure.},
                     readProc: proc(offset, size: uint64): seq[byte] {.closure.},
                     writeProc: proc(offset: uint64, data: seq[byte]) {.closure.},
                     limit: uint64 = 0): StableMemoryView =
  ## Test/alternate backend constructor. Offsets are relative to this view.
  StableMemoryView(limit: limit, sizeProc: sizeProc, readProc: readProc, writeProc: writeProc)

proc initBackendMemoryView*(backend: StableBackend, limit: uint64 = 0): StableMemoryView =
  ## Adapts a `StableBackend` (including a `VirtualStableBackend`) to a
  ## `StableMemoryView`. Writes auto-grow the backend to the required page
  ## before delegating, which preserves the growth semantics the stable
  ## structures depend on.
  if backend.isNil:
    raise newException(ValueError, "nil stable backend")
  let b = backend
  StableMemoryView(
    limit: limit,
    sizeProc: proc(): uint64 = b.sizePages * StablePageSize,
    readProc: proc(offset, size: uint64): seq[byte] =
      result = newSeq[byte](int(size))
      if size > 0:
        b.read(offset, addr result[0], size),
    writeProc: proc(offset: uint64, data: seq[byte]) =
      if data.len == 0: return
      let endOffset = offset + uint64(data.len)
      if endOffset < offset:
        raise newException(ValueError, "stable memory address overflow")
      let requiredPages = (endOffset + StablePageSize - 1) div StablePageSize
      let currentPages = b.sizePages
      if requiredPages > currentPages:
        if not b.grow(requiredPages - currentPages):
          raise newException(ValueError, "stable backend grow failed")
      b.write(offset, unsafeAddr data[0], uint64(data.len))
  )

proc view*(backend: StableBackend, limit: uint64 = 0): StableMemoryView =
  initBackendMemoryView(backend, limit)

proc checkRange(view: StableMemoryView, offset, size: uint64) =
  if offset > high(uint64) - size:
    raise newException(ValueError, "stable memory address overflow")
  if view.limit != 0 and (offset > view.limit or size > view.limit - offset):
    raise newException(ValueError, "stable memory view bounds exceeded")

proc backendSize(view: StableMemoryView): uint64 =
  if view.sizeProc.isNil: return 0
  result = view.sizeProc()
  if view.limit != 0 and result > view.limit: result = view.limit

proc readInto*(view: StableMemoryView, dst: var openArray[byte], offset: uint64) =
  view.checkRange(offset, uint64(dst.len))
  if view.readProc.isNil:
    raise newException(ValueError, "stable memory view is not readable")
  let data = view.readProc(offset, uint64(dst.len))
  if data.len != dst.len:
    raise newException(ValueError, "memory backend returned an invalid read length")
  for i in 0 ..< dst.len: dst[i] = data[i]

proc read*(view: StableMemoryView, offset, size: uint64): seq[byte] =
  view.checkRange(offset, size)
  if view.readProc.isNil:
    raise newException(ValueError, "stable memory view is not readable")
  let available = view.backendSize
  if offset > available or size > available - offset:
    raise newException(ValueError, "stable memory read exceeds allocated size")
  result = view.readProc(offset, size)
  if result.len != int(size):
    raise newException(ValueError, "memory backend returned an invalid read length")

proc write*(view: StableMemoryView, offset: uint64, data: openArray[byte]) =
  view.checkRange(offset, uint64(data.len))
  if view.writeProc.isNil:
    raise newException(ValueError, "stable memory view is not writable")
  view.writeProc(offset, @data)

proc size*(view: StableMemoryView): uint64 =
  view.backendSize
