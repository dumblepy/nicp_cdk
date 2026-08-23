## Compatibility facade for the stable-memory-native SBT2 B+Tree backend.
##
## An existing STBL v1 region is deliberately rejected by initialization.  Use
## `stable_table_migration` to copy it to a separate SBT2 memory view first.

import ./memory_view
import ./stable_btree

export stable_btree

type IcStableTable*[K, V] = IcStableBTreeMap[K, V]

proc initIcStableTable*[K, V](memory: StableMemoryView, cacheSlots: int = 16,
                              valueCodecId: uint32 = 0): IcStableTable[K, V] =
  initIcStableBTreeMap[K, V](memory, cacheSlots, valueCodecId)

proc initIcStableTable*[K, V](memory: StableMemoryView, codec: StableKeyCodec[K], cacheSlots: int = 16,
                              valueCodecId: uint32 = 0): IcStableTable[K, V] =
  initIcStableBTreeMap[K, V](memory, codec, cacheSlots, valueCodecId)

proc initIcStableTable*[K, V](baseOffset: uint64 = 0, limit: uint64 = 0,
                              cacheSlots: int = 16, valueCodecId: uint32 = 0): IcStableTable[K, V] =
  ## `baseOffset` remains for source compatibility.  New code should pass a
  ## bounded StableMemoryView directly to initIcStableBTreeMap.
  initIcStableBTreeMap[K, V](initRawMemoryView(baseOffset, limit), cacheSlots, valueCodecId)
