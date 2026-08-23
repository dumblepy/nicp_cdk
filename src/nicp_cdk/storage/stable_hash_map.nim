## Stable-memory-native exact-match map using linear hashing.
##
## Growth moves one bucket chain at a time; it never rehashes every entry in a
## single operation.  The directory is paged so opening the map reads only its
## fixed-size header, independent of the number of buckets or entries.

import std/endians
import ./serialization
import ./memory_view
import ./linear_hashing
import ./stable_hash

const
  HashMapMagic = [byte('S'), byte('H'), byte('M'), byte('2')]
  HashMapVersion* = 1'u32
  HashMapHeaderSize = 256'u64
  DirectoryPageSize = 1024'u64
  DirectoryEntries = 126
  BucketHeaderSize = 16'u64
  EntryHeaderSize = 24'u64
  DefaultBucketLoad* = 8'u32
  DefaultStableHashSeed* = StableHashSeed(k0: 0x0706050403020100'u64,
                                          k1: 0x0f0e0d0c0b0a0908'u64)

type
  HashMapHeader = object
    count, directoryHead, directoryTail, arenaEnd: uint64
    state: LinearHashState
  Bucket = object
    head: uint64
    count: uint64
  HashEntry = object
    next, hash: uint64
    keyLen, valueLen: uint32
  IcStableHashMap*[K, V] = object
    memory: StableMemoryView
    header: HashMapHeader
    seed: StableHashSeed
    valueCodecId: uint32
    maxBucketLoad: uint32

proc put32(data: var openArray[byte], at: int, value: uint32) =
  var x = value
  littleEndian32(addr data[at], addr x)

proc put64(data: var openArray[byte], at: int, value: uint64) =
  var x = value
  littleEndian64(addr data[at], addr x)

proc get32(data: openArray[byte], at: int): uint32 =
  littleEndian32(addr result, unsafeAddr data[at])

proc get64(data: openArray[byte], at: int): uint64 =
  littleEndian64(addr result, unsafeAddr data[at])

proc writeHeader[K, V](t: IcStableHashMap[K, V]) =
  var data = newSeq[byte](int(HashMapHeaderSize))
  for i in 0 .. 3: data[i] = HashMapMagic[i]
  data.put32(4, HashMapVersion)
  data.put32(8, SipHash24Id)
  data.put32(12, t.valueCodecId)
  data.put64(16, t.seed.k0); data.put64(24, t.seed.k1)
  data.put64(32, t.header.count)
  data.put32(40, t.header.state.level); data.put32(44, t.header.state.split)
  data.put64(48, t.header.directoryHead); data.put64(56, t.header.directoryTail)
  data.put64(64, t.header.arenaEnd); data.put32(72, t.maxBucketLoad)
  t.memory.write(0, data)

proc readHeader[K, V](t: var IcStableHashMap[K, V]): bool =
  if t.memory.size < HashMapHeaderSize: return false
  let data = t.memory.read(0, HashMapHeaderSize)
  for i in 0 .. 3:
    if data[i] != HashMapMagic[i]: return false
  if data.get32(4) != HashMapVersion: raise newException(ValueError, "unsupported SHM2 layout version")
  if data.get32(8) != SipHash24Id: raise newException(ValueError, "unsupported stable hash algorithm")
  if data.get32(12) != t.valueCodecId: raise newException(ValueError, "SHM2 value codec mismatch")
  if data.get64(16) != t.seed.k0 or data.get64(24) != t.seed.k1:
    raise newException(ValueError, "SHM2 hash seed mismatch")
  t.header.count = data.get64(32)
  t.header.state = LinearHashState(level: data.get32(40), split: data.get32(44))
  discard t.header.state.bucketCount # validates persisted state
  t.header.directoryHead = data.get64(48); t.header.directoryTail = data.get64(56)
  t.header.arenaEnd = data.get64(64); t.maxBucketLoad = data.get32(72)
  if t.maxBucketLoad == 0: raise newException(ValueError, "invalid SHM2 bucket load")
  if t.header.arenaEnd < HashMapHeaderSize or t.header.arenaEnd > t.memory.size:
    raise newException(ValueError, "invalid SHM2 allocator metadata")
  if t.header.directoryHead < HashMapHeaderSize or t.header.directoryTail < HashMapHeaderSize:
    raise newException(ValueError, "invalid SHM2 directory metadata")
  result = true

proc alloc[K, V](t: var IcStableHashMap[K, V], size: uint64, alignment: uint64 = 8): uint64 =
  let mask = alignment - 1
  if alignment == 0 or (alignment and mask) != 0: raise newException(ValueError, "invalid SHM2 alignment")
  if t.header.arenaEnd > high(uint64) - mask: raise newException(ValueError, "SHM2 address overflow")
  result = (t.header.arenaEnd + mask) and not mask
  if size > high(uint64) - result: raise newException(ValueError, "SHM2 allocation overflow")
  t.header.arenaEnd = result + size

proc readBucket[K, V](t: IcStableHashMap[K, V], address: uint64): Bucket =
  if address < HashMapHeaderSize or address > t.header.arenaEnd - BucketHeaderSize:
    raise newException(ValueError, "SHM2 bucket address out of bounds")
  let data = t.memory.read(address, BucketHeaderSize)
  result = Bucket(head: data.get64(0), count: data.get64(8))

proc writeBucket[K, V](t: IcStableHashMap[K, V], address: uint64, bucket: Bucket) =
  var data = newSeq[byte](int(BucketHeaderSize))
  data.put64(0, bucket.head); data.put64(8, bucket.count)
  t.memory.write(address, data)

proc readDirectoryPage[K, V](t: IcStableHashMap[K, V], address: uint64): seq[byte] =
  if address < HashMapHeaderSize or address > t.header.arenaEnd - DirectoryPageSize:
    raise newException(ValueError, "SHM2 directory page out of bounds")
  result = t.memory.read(address, DirectoryPageSize)
  if result.get32(8) > DirectoryEntries.uint32: raise newException(ValueError, "invalid SHM2 directory page")

proc bucketAddress[K, V](t: IcStableHashMap[K, V], index: uint64): uint64 =
  if index >= t.header.state.bucketCount: raise newException(ValueError, "SHM2 bucket index out of bounds")
  var pageAddress = t.header.directoryHead
  var remaining = index
  while pageAddress != 0:
    let page = t.readDirectoryPage(pageAddress)
    let used = uint64(page.get32(8))
    if remaining < used: return page.get64(16 + int(remaining) * 8)
    remaining -= used
    pageAddress = page.get64(0)
  raise newException(ValueError, "truncated SHM2 bucket directory")

proc appendBucketAddress[K, V](t: var IcStableHashMap[K, V], address: uint64) =
  var page = t.readDirectoryPage(t.header.directoryTail)
  let used = int(page.get32(8))
  if used < DirectoryEntries:
    page.put64(16 + used * 8, address); page.put32(8, uint32(used + 1))
    t.memory.write(t.header.directoryTail, page)
    return
  let nextPage = t.alloc(DirectoryPageSize)
  var next = newSeq[byte](int(DirectoryPageSize)); next.put32(8, 1); next.put64(16, address)
  t.memory.write(nextPage, next)
  page.put64(0, nextPage); t.memory.write(t.header.directoryTail, page)
  t.header.directoryTail = nextPage

proc newBucket[K, V](t: var IcStableHashMap[K, V]): uint64 =
  result = t.alloc(BucketHeaderSize)
  t.writeBucket(result, Bucket())
  t.appendBucketAddress(result)

proc readEntry[K, V](t: IcStableHashMap[K, V], address: uint64): HashEntry =
  if address < HashMapHeaderSize or address > t.header.arenaEnd - EntryHeaderSize:
    raise newException(ValueError, "SHM2 entry address out of bounds")
  let data = t.memory.read(address, EntryHeaderSize)
  result = HashEntry(next: data.get64(0), hash: data.get64(8), keyLen: data.get32(16), valueLen: data.get32(20))
  let payload = uint64(result.keyLen) + uint64(result.valueLen)
  if payload > t.header.arenaEnd - address - EntryHeaderSize:
    raise newException(ValueError, "SHM2 entry payload out of bounds")

proc writeNext[K, V](t: IcStableHashMap[K, V], address, next: uint64) =
  if address < HashMapHeaderSize or address > t.header.arenaEnd - 8'u64:
    raise newException(ValueError, "SHM2 entry address out of bounds")
  var data = newSeq[byte](8); data.put64(0, next); t.memory.write(address, data)

proc keyData[K, V](t: IcStableHashMap[K, V], address: uint64, entry: HashEntry): seq[byte] =
  t.memory.read(address + EntryHeaderSize, uint64(entry.keyLen))

proc valueData[K, V](t: IcStableHashMap[K, V], address: uint64, entry: HashEntry): seq[byte] =
  t.memory.read(address + EntryHeaderSize + uint64(entry.keyLen), uint64(entry.valueLen))

proc writeEntry[K, V](t: var IcStableHashMap[K, V], next, hash: uint64,
                       key, value: openArray[byte]): uint64 =
  if key.len > int(high(uint32)) or value.len > int(high(uint32)):
    raise newException(ValueError, "SHM2 key or value is too large")
  result = t.alloc(EntryHeaderSize + uint64(key.len) + uint64(value.len))
  var data = newSeq[byte](int(EntryHeaderSize) + key.len + value.len)
  data.put64(0, next); data.put64(8, hash); data.put32(16, uint32(key.len)); data.put32(20, uint32(value.len))
  for i, b in key: data[int(EntryHeaderSize) + i] = b
  for i, b in value: data[int(EntryHeaderSize) + key.len + i] = b
  t.memory.write(result, data)

proc findEntry[K, V](t: IcStableHashMap[K, V], key: openArray[byte], hash: uint64): (uint64, uint64, uint64) =
  ## Returns bucket address, previous entry, and matching entry (zero if absent).
  let bucketAddress = t.bucketAddress(t.header.state.bucketIndex(hash))
  var previous = 0'u64
  var current = t.readBucket(bucketAddress).head
  var remaining = t.header.count + 1
  while current != 0:
    if remaining == 0: raise newException(ValueError, "cyclic SHM2 bucket chain")
    dec remaining
    let entry = t.readEntry(current)
    if entry.hash == hash and t.keyData(current, entry) == @key:
      return (bucketAddress, previous, current)
    previous = current; current = entry.next
  (bucketAddress, previous, 0)

proc splitOnce[K, V](t: var IcStableHashMap[K, V]) =
  let oldIndex = t.header.state.splitBucket
  let oldAddress = t.bucketAddress(oldIndex)
  let newIndex = t.header.state.bucketCount
  let newAddress = t.newBucket
  let oldBucket = t.readBucket(oldAddress)
  var oldHead = 0'u64; var oldCount = 0'u64
  var newHead = 0'u64; var newCount = 0'u64
  var current = oldBucket.head
  var remaining = oldBucket.count + 1
  while current != 0:
    if remaining == 0: raise newException(ValueError, "cyclic SHM2 bucket chain")
    dec remaining
    let entry = t.readEntry(current)
    let next = entry.next
    ## This is the bucket currently being split, so routing uses the next
    ## level mask even though `state.split` is advanced only after the chain
    ## has been rewritten.
    let target = entry.hash and ((1'u64 shl (t.header.state.level + 1)) - 1)
    if target == oldIndex:
      t.writeNext(current, oldHead); oldHead = current; inc oldCount
    elif target == newIndex:
      t.writeNext(current, newHead); newHead = current; inc newCount
    else:
      raise newException(ValueError, "invalid SHM2 split routing")
    current = next
  t.writeBucket(oldAddress, Bucket(head: oldHead, count: oldCount))
  t.writeBucket(newAddress, Bucket(head: newHead, count: newCount))
  t.header.state.advanceSplit

proc initialize[K, V](t: var IcStableHashMap[K, V]) =
  t.header = HashMapHeader(arenaEnd: HashMapHeaderSize,
                           state: LinearHashState(level: 1, split: 0))
  let directory = t.alloc(DirectoryPageSize)
  t.memory.write(directory, newSeq[byte](int(DirectoryPageSize)))
  t.header.directoryHead = directory; t.header.directoryTail = directory
  discard t.newBucket; discard t.newBucket
  t.writeHeader

proc initIcStableHashMap*[K, V](memory: StableMemoryView = initRawMemoryView(),
                                seed: StableHashSeed = DefaultStableHashSeed,
                                maxBucketLoad: uint32 = DefaultBucketLoad,
                                valueCodecId: uint32 = 0): IcStableHashMap[K, V] =
  if maxBucketLoad == 0: raise newException(ValueError, "maxBucketLoad must be positive")
  result.memory = memory; result.seed = seed; result.valueCodecId = valueCodecId; result.maxBucketLoad = maxBucketLoad
  if result.readHeader: return
  result.initialize

proc len*[K, V](t: IcStableHashMap[K, V]): int = int(t.header.count)

proc hasKey*[K, V](t: IcStableHashMap[K, V], key: K): bool =
  let keyBytes = serialize(key)
  let (_, _, found) = t.findEntry(keyBytes, sipHash24(t.seed, keyBytes))
  found != 0

proc `[]`*[K, V](t: IcStableHashMap[K, V], key: K): V =
  let keyBytes = serialize(key)
  let (_, _, found) = t.findEntry(keyBytes, sipHash24(t.seed, keyBytes))
  if found == 0: raise newException(KeyError, "key not found")
  let entry = t.readEntry(found)
  var position = 0
  deserialize[V](t.valueData(found, entry), position)

proc `[]=`*[K, V](t: var IcStableHashMap[K, V], key: K, value: V) =
  let keyBytes = serialize(key); let valueBytes = serialize(value); let hash = sipHash24(t.seed, keyBytes)
  let (bucketAddress, previous, found) = t.findEntry(keyBytes, hash)
  if found != 0:
    let old = t.readEntry(found)
    let replacement = t.writeEntry(old.next, hash, keyBytes, valueBytes)
    if previous == 0:
      var bucket = t.readBucket(bucketAddress); bucket.head = replacement; t.writeBucket(bucketAddress, bucket)
    else:
      t.writeNext(previous, replacement)
    t.writeHeader
    return
  var bucket = t.readBucket(bucketAddress)
  let entry = t.writeEntry(bucket.head, hash, keyBytes, valueBytes)
  bucket.head = entry; inc bucket.count; t.writeBucket(bucketAddress, bucket); inc t.header.count
  if t.header.state.bucketCount <= high(uint64) div uint64(t.maxBucketLoad) and
     t.header.count > t.header.state.bucketCount * uint64(t.maxBucketLoad):
    t.splitOnce
  t.writeHeader

iterator pairs*[K, V](t: IcStableHashMap[K, V]): (K, V) =
  for index in 0'u64 ..< t.header.state.bucketCount:
    var current = t.readBucket(t.bucketAddress(index)).head
    var remaining = t.header.count + 1
    while current != 0:
      if remaining == 0: raise newException(ValueError, "cyclic SHM2 bucket chain")
      dec remaining
      let entry = t.readEntry(current)
      var keyPosition = 0; var valuePosition = 0
      yield (deserialize[K](t.keyData(current, entry), keyPosition),
             deserialize[V](t.valueData(current, entry), valuePosition))
      current = entry.next

iterator keys*[K, V](t: IcStableHashMap[K, V]): K =
  for key, _ in t.pairs: yield key

iterator values*[K, V](t: IcStableHashMap[K, V]): V =
  for _, value in t.pairs: yield value

proc clear*[K, V](t: var IcStableHashMap[K, V]) =
  ## The physical stable-memory allocation remains, but the logical arena is
  ## reset and its first pages are reused.
  t.initialize
