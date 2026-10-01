discard """
  cmd: "nim c -r --skipUserCfg $file"
"""

import std/unittest
import ../../src/nicp_cdk/storage/stable_backend

suite "stable backend":
  test "VecStableBackend grow, read, write, and bounds":
    let backend = newVecStableBackend()
    check backend.sizePages == 0
    check backend.grow(2)
    check backend.sizePages == 2
    check backend.grow(0)

    var payload = [1'u8, 2, 3, 4]
    backend.write(0, addr payload[0], uint64(payload.len))
    var output: array[4, byte]
    backend.read(0, addr output[0], uint64(output.len))
    check output == payload

    ## zero-length I/O is a no-op even with a nil buffer
    backend.read(100, nil, 0)
    backend.write(100, nil, 0)

    expect ValueError:
      var oversized: array[8, byte]
      backend.read(uint64(2 * StablePageSize - 4), addr oversized[0], 8)
    expect ValueError:
      var oversized: array[8, byte]
      backend.write(uint64(2 * StablePageSize - 4), addr oversized[0], 8)

  test "OffsetStableBackend partitions a page-aligned subregion":
    let raw = newVecStableBackend()
    check raw.grow(4)
    let region = newOffsetStableBackend(raw, StablePageSize, 2 * StablePageSize)
    check region.sizePages == 2

    var payload = [9'u8, 8, 7]
    region.write(0, addr payload[0], uint64(payload.len))
    var output: array[3, byte]
    region.read(0, addr output[0], uint64(output.len))
    check output == payload

    ## the write lands inside the parent region at the configured base offset
    var physical: array[3, byte]
    raw.read(StablePageSize, addr physical[0], uint64(physical.len))
    check physical == payload

    expect ValueError:
      var value: array[2, byte]
      region.write(2 * StablePageSize, addr value[0], 2)
    expect ValueError:
      var value: array[2, byte]
      region.read(2 * StablePageSize, addr value[0], 2)
    check not region.grow(1)

    expect ValueError:
      discard newOffsetStableBackend(raw, 1)
