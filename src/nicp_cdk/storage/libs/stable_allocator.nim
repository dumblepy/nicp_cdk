## Persistent append allocator used by the SBT layout.
## Free-list reuse is intentionally kept behind this module's API so the
## on-disk header can gain bins without changing tree code.

import ./memory_view

type StableAllocator* = object
  arenaEnd*: uint64

proc initStableAllocator*(arenaEnd: uint64): StableAllocator =
  StableAllocator(arenaEnd: arenaEnd)

proc allocate*(allocator: var StableAllocator, view: StableMemoryView,
               size, alignment: uint64): uint64 =
  if alignment == 0 or (alignment and (alignment - 1)) != 0:
    raise newException(ValueError, "alignment must be a power of two")
  let padding = (alignment - (allocator.arenaEnd and (alignment - 1))) and (alignment - 1)
  if allocator.arenaEnd > high(uint64) - padding - size:
    raise newException(ValueError, "stable allocator overflow")
  result = allocator.arenaEnd + padding
  discard view # view bounds are enforced by the first write.
  allocator.arenaEnd = result + size
