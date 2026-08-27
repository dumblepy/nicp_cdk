## Stable-memory-native B+Tree.  Only the superblock is loaded at open time;
## nodes and values are read by address on demand.

import std/endians
import std/options
import ./serialization
import ./memory_view
import ./stable_allocator
import ./stable_key_codec
import ../../ic_types/ic_principal

const
  BTreeMagic = [byte('S'), byte('B'), byte('T')]
  BTreeVersion* = 1'u16
  SuperblockSize = 256'u64
  DefaultNodeSize* = 1024'u32
  NodeHeaderSize = 48
  SlotSize = 32
  LeafNode = 1'u8
  InternalNode = 2'u8

type
  BTreeHeader = object
    count, rootAddr, firstLeaf, lastLeaf, blobFreeHead, arenaEnd: uint64
    height: uint32
  Slot = object
    keyOff: uint64
    keyLen: uint32
    valueOff: uint64
    valueLen: uint32
    child: uint64
  Node = object
    kind: uint8
    prev, next, firstChild: uint64
    slots: seq[Slot]
  NodeCacheEntry = object
    address: uint64
    node: Node
    valid: bool
  NodeCache = ref object
    entries: seq[NodeCacheEntry]
  StableKeyCodec*[K] = object
    id*: uint32
    encode*: proc(key: K): seq[byte] {.closure.}
    decode*: proc(data: openArray[byte]): K {.closure.}
  IcStableTable*[K, V] = object
    memory: StableMemoryView
    header: BTreeHeader
    nodeSize: uint32
    keyCodecId: uint32
    valueCodecId: uint32
    cache: NodeCache
    codec: StableKeyCodec[K]
    builtinCodec: bool

proc put32(data: var openArray[byte], at: int, value: uint32) =
  var x = value; littleEndian32(addr data[at], addr x)
proc put64(data: var openArray[byte], at: int, value: uint64) =
  var x = value; littleEndian64(addr data[at], addr x)
proc get32(data: openArray[byte], at: int): uint32 =
  littleEndian32(addr result, unsafeAddr data[at])
proc get64(data: openArray[byte], at: int): uint64 =
  littleEndian64(addr result, unsafeAddr data[at])

proc ensureValidNodeSize(nodeSize: uint32) =
  if nodeSize < 256 or (nodeSize and (nodeSize - 1)) != 0:
    raise newException(ValueError, "invalid SBT node size")

proc capacity(t: IcStableTable): int = (int(t.nodeSize) - NodeHeaderSize) div SlotSize

proc encodeKey[K, V](t: IcStableTable[K, V], key: K): seq[byte] =
  ## Avoid an indirect closure call for built-in codecs. Besides reducing the
  ## hot-path overhead, this keeps the default codec path compatible with the
  ## WASM ABI used by the example canister.
  when K is string:
    return stableKeyEncode(key)
  elif K is bool or K is char or K is SomeUnsignedInt or K is SomeSignedInt or K is Principal:
    if t.keyCodecId == stableKeyCodecId(K): return stableKeyEncode(key)
  t.codec.encode(key)

proc decodeKey[K, V](t: IcStableTable[K, V], data: openArray[byte]): K =
  when K is string:
    return stableKeyDecode[K](data)
  elif K is bool or K is char or K is SomeUnsignedInt or K is SomeSignedInt or K is Principal:
    if t.keyCodecId == stableKeyCodecId(K): return stableKeyDecode[K](data)
  t.codec.decode(data)

proc writeHeader[K, V](t: IcStableTable[K, V]) =
  var b = newSeq[byte](int(SuperblockSize))
  for i in 0 .. 2: b[i] = BTreeMagic[i]
  b.put32(4, uint32(BTreeVersion)); b.put32(8, t.nodeSize)
  b.put32(12, t.keyCodecId); b.put32(16, t.valueCodecId)
  b.put64(24, t.header.count); b.put64(32, t.header.rootAddr)
  b.put32(40, t.header.height); b.put64(48, t.header.firstLeaf)
  b.put64(56, t.header.lastLeaf); b.put64(64, t.header.blobFreeHead); b.put64(72, t.header.arenaEnd)
  t.memory.write(0, b)

proc readHeader[K, V](t: var IcStableTable[K, V]): bool =
  if t.memory.size < SuperblockSize: return false
  let b = t.memory.read(0, SuperblockSize)
  for i in 0 .. 2:
    if b[i] != BTreeMagic[i]: return false
  if b.get32(4) != uint32(BTreeVersion):
    raise newException(ValueError, "unsupported SBT layout version")
  t.nodeSize = b.get32(8)
  ensureValidNodeSize(t.nodeSize)
  let storedKeyCodecId = b.get32(12)
  if storedKeyCodecId != t.keyCodecId: raise newException(ValueError, "SBT key codec mismatch")
  let storedValueCodecId = b.get32(16)
  if storedValueCodecId != t.valueCodecId: raise newException(ValueError, "SBT value codec mismatch")
  t.keyCodecId = storedKeyCodecId; t.valueCodecId = storedValueCodecId
  t.header.count = b.get64(24); t.header.rootAddr = b.get64(32)
  t.header.height = b.get32(40); t.header.firstLeaf = b.get64(48); t.header.lastLeaf = b.get64(56); t.header.blobFreeHead = b.get64(64)
  t.header.arenaEnd = b.get64(72)
  if t.header.arenaEnd < SuperblockSize or t.header.arenaEnd > t.memory.size:
    raise newException(ValueError, "invalid SBT allocator metadata")
  result = true

proc readNode[K, V](t: IcStableTable[K, V], address: uint64): Node =
  if not t.cache.isNil and t.cache.entries.len > 0:
    let slot = int((address div uint64(t.nodeSize)) mod uint64(t.cache.entries.len))
    let cached = t.cache.entries[slot]
    if cached.valid and cached.address == address: return cached.node
  if address < SuperblockSize or address > t.memory.size - uint64(t.nodeSize):
    raise newException(ValueError, "SBT node address out of bounds")
  let b = t.memory.read(address, uint64(t.nodeSize))
  result.kind = b[0]
  if result.kind != LeafNode and result.kind != InternalNode: raise newException(ValueError, "invalid SBT node type")
  let n = int(b.get32(4))
  if n > t.capacity: raise newException(ValueError, "invalid SBT node slot count")
  result.prev = b.get64(8); result.next = b.get64(16); result.firstChild = b.get64(24)
  result.slots = newSeq[Slot](n)
  for i in 0 ..< n:
    let p = NodeHeaderSize + i * SlotSize
    result.slots[i] = Slot(keyOff: b.get64(p), keyLen: b.get32(p + 8), valueOff: b.get64(p + 12), valueLen: b.get32(p + 20), child: b.get64(p + 24))
  if not t.cache.isNil and t.cache.entries.len > 0:
    let slot = int((address div uint64(t.nodeSize)) mod uint64(t.cache.entries.len))
    t.cache.entries[slot] = NodeCacheEntry(address: address, node: result, valid: true)

proc writeNode[K, V](t: IcStableTable[K, V], address: uint64, node: Node) =
  if node.slots.len > t.capacity: raise newException(ValueError, "SBT node overflow")
  var b = newSeq[byte](int(t.nodeSize)); b[0] = node.kind; b.put32(4, uint32(node.slots.len))
  b.put64(8, node.prev); b.put64(16, node.next); b.put64(24, node.firstChild)
  for i, s in node.slots:
    let p = NodeHeaderSize + i * SlotSize
    b.put64(p, s.keyOff); b.put32(p + 8, s.keyLen); b.put64(p + 12, s.valueOff); b.put32(p + 20, s.valueLen); b.put64(p + 24, s.child)
  t.memory.write(address, b)
  if not t.cache.isNil and t.cache.entries.len > 0:
    let slot = int((address div uint64(t.nodeSize)) mod uint64(t.cache.entries.len))
    t.cache.entries[slot] = NodeCacheEntry(address: address, node: node, valid: true)

proc alloc[K, V](t: var IcStableTable[K, V], size, alignment: uint64): uint64 =
  var a = initStableAllocator(t.header.arenaEnd)
  result = a.allocate(t.memory, size, alignment); t.header.arenaEnd = a.arenaEnd
proc readBlobHeader[K, V](t: IcStableTable[K, V], address: uint64): (uint64, uint64) =
  if address < SuperblockSize or address > t.memory.size - 16'u64:
    raise newException(ValueError, "SBT blob header out of bounds")
  let data = t.memory.read(address, 16)
  (data.get64(0), data.get64(8)) # payload capacity, next free header

proc writeBlobHeader[K, V](t: IcStableTable[K, V], address, capacity, next: uint64) =
  var data = newSeq[byte](16); data.put64(0, capacity); data.put64(8, next)
  t.memory.write(address, data)

proc writeBlob[K, V](t: var IcStableTable[K, V], data: openArray[byte]): uint64 =
  ## A first-fit free-list keeps update-heavy tables from becoming append-only.
  var previous = 0'u64
  var current = t.header.blobFreeHead
  while current != 0:
    let (capacity, next) = t.readBlobHeader(current)
    if capacity >= uint64(data.len):
      if previous == 0: t.header.blobFreeHead = next
      else:
        let (previousCapacity, _) = t.readBlobHeader(previous)
        t.writeBlobHeader(previous, previousCapacity, next)
      result = current + 16'u64
      t.memory.write(result, data)
      return
    previous = current; current = next
  let headerAddress = t.alloc(16'u64 + uint64(data.len), 8)
  t.writeBlobHeader(headerAddress, uint64(data.len), 0)
  result = headerAddress + 16'u64
  t.memory.write(result, data)

proc freeBlob[K, V](t: var IcStableTable[K, V], payloadAddress: uint64) =
  if payloadAddress < SuperblockSize + 16'u64:
    raise newException(ValueError, "invalid SBT blob address")
  let headerAddress = payloadAddress - 16'u64
  let (capacity, _) = t.readBlobHeader(headerAddress)
  t.writeBlobHeader(headerAddress, capacity, t.header.blobFreeHead)
  t.header.blobFreeHead = headerAddress
proc readKey[K, V](t: IcStableTable[K, V], s: Slot): seq[byte] =
  if s.keyOff > t.memory.size or uint64(s.keyLen) > t.memory.size - s.keyOff: raise newException(ValueError, "SBT key blob out of bounds")
  t.memory.read(s.keyOff, uint64(s.keyLen))
proc bytesCompare(a, b: openArray[byte]): int =
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]: return (if a[i] < b[i]: -1 else: 1)
  system.cmp(a.len, b.len)
proc lower[K, V](t: IcStableTable[K, V], n: Node, key: openArray[byte]): int =
  var lo = 0; var hi = n.slots.len
  while lo < hi:
    let mid = (lo + hi) div 2
    if bytesCompare(t.readKey(n.slots[mid]), key) < 0: lo = mid + 1 else: hi = mid
  lo
proc childIndex[K, V](t: IcStableTable[K, V], n: Node, key: openArray[byte]): int =
  ## Internal separators are the first key of their right child, so equality
  ## must select that right child (upper-bound semantics).
  var lo = 0; var hi = n.slots.len
  while lo < hi:
    let mid = (lo + hi) div 2
    if bytesCompare(t.readKey(n.slots[mid]), key) <= 0: lo = mid + 1 else: hi = mid
  lo
proc newNode[K, V](t: var IcStableTable[K, V], kind: uint8): uint64 =
  ensureValidNodeSize(t.nodeSize)
  result = t.alloc(uint64(t.nodeSize), uint64(t.nodeSize)); t.writeNode(result, Node(kind: kind))

proc initIcStableTable*[K, V](memory: StableMemoryView, codec: StableKeyCodec[K], cacheSlots: int = 16,
                              valueCodecId: uint32 = 0): IcStableTable[K, V] =
  if cacheSlots < 0: raise newException(ValueError, "cacheSlots must not be negative")
  if codec.id == 0 or codec.encode.isNil or codec.decode.isNil: raise newException(ValueError, "invalid StableKeyCodec")
  result.memory = memory; result.nodeSize = DefaultNodeSize; result.keyCodecId = codec.id; result.valueCodecId = valueCodecId; result.codec = codec
  if not result.readHeader:
    ensureValidNodeSize(result.nodeSize)
    result.header.arenaEnd = SuperblockSize
    result.writeHeader
  if cacheSlots > 0:
    new(result.cache)
    result.cache.entries = newSeq[NodeCacheEntry](cacheSlots)

proc initIcStableTable*[K, V](memory: StableMemoryView = initRawMemoryView(), cacheSlots: int = 16,
                              valueCodecId: uint32 = 0): IcStableTable[K, V] =
  let codec = StableKeyCodec[K](id: stableKeyCodecId(K),
    encode: proc(key: K): seq[byte] = stableKeyEncode(key),
    decode: proc(data: openArray[byte]): K = stableKeyDecode[K](data))
  result = initIcStableTable[K, V](memory, codec, cacheSlots, valueCodecId)
  result.builtinCodec = true

proc len*[K, V](t: IcStableTable[K, V]): int = int(t.header.count)
proc hasKey*[K, V](t: IcStableTable[K, V], key: K): bool {.noinline.} =
  let q = t.encodeKey(key); var nodeAddr = t.header.rootAddr
  while nodeAddr != 0:
    let n = t.readNode(nodeAddr)
    if n.kind == LeafNode:
      let i = t.lower(n, q)
      return i < n.slots.len and bytesCompare(t.readKey(n.slots[i]), q) == 0
    let i = t.childIndex(n, q)
    nodeAddr = if i == 0: n.firstChild else: n.slots[i - 1].child
  false

proc `[]`*[K, V](t: IcStableTable[K, V], key: K): V {.noinline.} =
  let q = t.encodeKey(key); var nodeAddr = t.header.rootAddr
  while nodeAddr != 0:
    let n = t.readNode(nodeAddr)
    if n.kind == LeafNode:
      let i = t.lower(n, q)
      if i == n.slots.len or bytesCompare(t.readKey(n.slots[i]), q) != 0: raise newException(KeyError, "key not found")
      let s = n.slots[i]; let data = t.memory.read(s.valueOff, uint64(s.valueLen)); var p = 0; return deserialize[V](data, p)
    let i = t.childIndex(n, q)
    nodeAddr = if i == 0: n.firstChild else: n.slots[i - 1].child
  raise newException(KeyError, "key not found")

proc lowerBound*[K, V](t: IcStableTable[K, V], key: K): Option[(K, V)] =
  ## Returns the first entry whose key is not smaller than `key`.
  let query = t.encodeKey(key)
  var nodeAddr = t.header.rootAddr
  while nodeAddr != 0:
    let node = t.readNode(nodeAddr)
    if node.kind == LeafNode:
      let index = t.lower(node, query)
      if index == node.slots.len:
        nodeAddr = node.next
        if nodeAddr == 0: return none((K, V))
        let nextLeaf = t.readNode(nodeAddr)
        if nextLeaf.slots.len == 0: return none((K, V))
        let slot = nextLeaf.slots[0]
        let valueData = t.memory.read(slot.valueOff, uint64(slot.valueLen)); var valuePos = 0
        return some((t.decodeKey(t.readKey(slot)), deserialize[V](valueData, valuePos)))
      let slot = node.slots[index]
      let valueData = t.memory.read(slot.valueOff, uint64(slot.valueLen)); var valuePos = 0
      return some((t.decodeKey(t.readKey(slot)), deserialize[V](valueData, valuePos)))
    let index = t.childIndex(node, query)
    nodeAddr = if index == 0: node.firstChild else: node.slots[index - 1].child
  none((K, V))

proc insertIntoParent[K, V](t: var IcStableTable[K, V], path: seq[uint64], childIndexes: seq[int],
                            separator: Slot, rightAddr: uint64) =
  var sep = separator; var right = rightAddr
  for level in countdown(path.high, 0):
    let parentAddr = path[level]; var parent = t.readNode(parentAddr)
    let i = childIndexes[level]
    parent.slots.insert(sep, i)
    parent.slots[i].child = right
    if parent.slots.len <= t.capacity:
      t.writeNode(parentAddr, parent); return
    let middle = parent.slots.len div 2
    let promoted = parent.slots[middle]
    var rightNode = Node(kind: InternalNode, firstChild: promoted.child)
    if middle + 1 < parent.slots.len: rightNode.slots = parent.slots[middle + 1 .. ^1]
    parent.slots.setLen(middle)
    let sibling = t.newNode(InternalNode)
    t.writeNode(parentAddr, parent); t.writeNode(sibling, rightNode)
    sep = promoted; right = sibling
  let root = t.newNode(InternalNode)
  let n = Node(kind: InternalNode, firstChild: t.header.rootAddr, slots: @[sep])
  var rootNode = n; rootNode.slots[0].child = right
  t.writeNode(root, rootNode); t.header.rootAddr = root; inc t.header.height

proc `[]=`*[K, V](t: var IcStableTable[K, V], key: K, value: V) {.noinline.} =
  let keyBytes = t.encodeKey(key)
  let valueBytes = serialize(value)
  if t.header.rootAddr == 0:
    let keyOff = t.writeBlob(keyBytes); let valueOff = t.writeBlob(valueBytes)
    let root = t.newNode(LeafNode)
    t.writeNode(root, Node(kind: LeafNode, slots: @[Slot(keyOff: keyOff, keyLen: uint32(keyBytes.len), valueOff: valueOff, valueLen: uint32(valueBytes.len))]))
    t.header.rootAddr = root; t.header.firstLeaf = root; t.header.lastLeaf = root
    t.header.height = 1; t.header.count = 1; t.writeHeader
  else:
    block inserted:
      var nodeAddr = t.header.rootAddr; var path: seq[uint64] = @[]; var childIndexes: seq[int] = @[]
      while true:
        let n = t.readNode(nodeAddr)
        if n.kind == LeafNode: break
        let i = t.childIndex(n, keyBytes)
        path.add(nodeAddr); childIndexes.add(i)
        nodeAddr = if i == 0: n.firstChild else: n.slots[i - 1].child
      var leaf = t.readNode(nodeAddr); let pos = t.lower(leaf, keyBytes)
      let valueOff = t.writeBlob(valueBytes)
      if pos < leaf.slots.len and bytesCompare(t.readKey(leaf.slots[pos]), keyBytes) == 0:
        let oldValueOff = leaf.slots[pos].valueOff
        leaf.slots[pos].valueOff = valueOff; leaf.slots[pos].valueLen = uint32(valueBytes.len)
        t.freeBlob(oldValueOff)
        t.writeNode(nodeAddr, leaf); t.writeHeader
        break inserted
      let keyOff = t.writeBlob(keyBytes)
      leaf.slots.insert(Slot(keyOff: keyOff, keyLen: uint32(keyBytes.len), valueOff: valueOff, valueLen: uint32(valueBytes.len)), pos)
      inc t.header.count
      if leaf.slots.len <= t.capacity:
        t.writeNode(nodeAddr, leaf); t.writeHeader
        break inserted
      let cut = leaf.slots.len div 2
      var rightLeaf = Node(kind: LeafNode, prev: nodeAddr, next: leaf.next, slots: leaf.slots[cut .. ^1])
      leaf.slots.setLen(cut)
      let rightAddr = t.newNode(LeafNode)
      leaf.next = rightAddr
      if rightLeaf.next != 0:
        var nextLeaf = t.readNode(rightLeaf.next); nextLeaf.prev = rightAddr; t.writeNode(rightLeaf.next, nextLeaf)
      else: t.header.lastLeaf = rightAddr
      t.writeNode(nodeAddr, leaf); t.writeNode(rightAddr, rightLeaf)
      let first = rightLeaf.slots[0]
      let separator = Slot(keyOff: first.keyOff, keyLen: first.keyLen)
      if path.len == 0:
        let root = t.newNode(InternalNode)
        t.writeNode(root, Node(kind: InternalNode, firstChild: nodeAddr, slots: @[Slot(keyOff: separator.keyOff, keyLen: separator.keyLen, child: rightAddr)]))
        t.header.rootAddr = root; inc t.header.height
      else:
        t.insertIntoParent(path, childIndexes, separator, rightAddr)
      t.writeHeader

iterator pairs*[K, V](t: IcStableTable[K, V]): (K, V) =
  var nodeAddr = t.header.firstLeaf
  while nodeAddr != 0:
    let leaf = t.readNode(nodeAddr)
    for slot in leaf.slots:
      let key = t.decodeKey(t.readKey(slot))
      let data = t.memory.read(slot.valueOff, uint64(slot.valueLen)); var p = 0
      yield (key, deserialize[V](data, p))
    nodeAddr = leaf.next

iterator keys*[K, V](t: IcStableTable[K, V]): K =
  for key, _ in t.pairs: yield key
iterator values*[K, V](t: IcStableTable[K, V]): V =
  for _, value in t.pairs: yield value

iterator range*[K, V](t: IcStableTable[K, V], startKey, endKey: K): (K, V) =
  ## Iterates `[startKey, endKey)` in stable-key order.
  let start = t.encodeKey(startKey)
  let finish = t.encodeKey(endKey)
  if bytesCompare(start, finish) < 0:
    block done:
      var nodeAddr = t.header.rootAddr
      while nodeAddr != 0:
        let node = t.readNode(nodeAddr)
        if node.kind == LeafNode:
          let index = t.lower(node, start)
          var leaf = node
          var slotIndex = index
          while true:
            while slotIndex < leaf.slots.len:
              let slot = leaf.slots[slotIndex]
              if bytesCompare(t.readKey(slot), finish) >= 0: break done
              let valueData = t.memory.read(slot.valueOff, uint64(slot.valueLen)); var valuePos = 0
              yield (t.decodeKey(t.readKey(slot)), deserialize[V](valueData, valuePos))
              inc slotIndex
            if leaf.next == 0: break done
            leaf = t.readNode(leaf.next); slotIndex = 0
        let index = t.childIndex(node, start)
        nodeAddr = if index == 0: node.firstChild else: node.slots[index - 1].child

proc clear*[K, V](t: var IcStableTable[K, V]) =
  ## Stable memory cannot shrink; resetting the arena makes this view reusable.
  ## Reset the node geometry too: a cleared view must never retain a legacy
  ## non-page-aligned node size from an interrupted/older deployment.
  t.nodeSize = DefaultNodeSize
  t.header = BTreeHeader(arenaEnd: SuperblockSize)
  t.writeHeader
