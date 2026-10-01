## IC `stable64_*` syscall backend. Native builds deliberately do not emulate it;
## use `VecStableBackend` in unit tests instead.

import ./stable_backend

when defined(wasm32):
  import ../../ic0/ic0

  proc stableReadRaw*(dst: pointer; offset, size: uint64) =
    if size > 0 and dst.isNil:
      raise newException(ValueError, "nil stable read destination")
    ic0_stable64_read(cast[uint64](dst), offset, size)

  proc stableWriteRaw*(offset: uint64; src: pointer; size: uint64) =
    if size > 0 and src.isNil:
      raise newException(ValueError, "nil stable write source")
    ic0_stable64_write(offset, cast[uint64](src), size)
else:
  proc stableReadRaw*(dst: pointer; offset, size: uint64) =
    discard dst; discard offset; discard size
    raise newException(CatchableError, "IC stable memory is only available on wasm32")

  proc stableWriteRaw*(offset: uint64; src: pointer; size: uint64) =
    discard offset; discard src; discard size
    raise newException(CatchableError, "IC stable memory is only available on wasm32")

type IcStableBackend* = ref object of StableBackend

proc newIcStableBackend*(): IcStableBackend = IcStableBackend()

method sizePages*(backend: IcStableBackend): uint64 =
  when defined(wasm32):
    ic0_stable64_size()
  else:
    raise newException(CatchableError, "IC stable memory is only available on wasm32")

method grow*(backend: IcStableBackend; pages: uint64): bool =
  when defined(wasm32):
    ic0_stable64_grow(pages) != high(uint64)
  else:
    raise newException(CatchableError, "IC stable memory is only available on wasm32")

method read*(backend: IcStableBackend; offset: uint64; dst: pointer; size: uint64) =
  stableReadRaw(dst, offset, size)

method write*(backend: IcStableBackend; offset: uint64; src: pointer; size: uint64) =
  stableWriteRaw(offset, src, size)
