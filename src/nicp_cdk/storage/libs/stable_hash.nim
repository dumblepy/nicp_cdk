## Versioned deterministic SipHash-2-4 primitive for stable hash structures.

const SipHash24Id* = 1'u32

type StableHashSeed* = object
  k0*, k1*: uint64

proc rotl(x: uint64, n: int): uint64 {.inline.} = (x shl n) or (x shr (64 - n))
template round(v0, v1, v2, v3: untyped) =
  v0 = v0 + v1; v1 = rotl(v1, 13); v1 = v1 xor v0; v0 = rotl(v0, 32)
  v2 = v2 + v3; v3 = rotl(v3, 16); v3 = v3 xor v2
  v0 = v0 + v3; v3 = rotl(v3, 21); v3 = v3 xor v0
  v2 = v2 + v1; v1 = rotl(v1, 17); v1 = v1 xor v2; v2 = rotl(v2, 32)
proc little(data: openArray[byte], at: int): uint64 =
  for i in 0 ..< 8: result = result or (uint64(data[at + i]) shl (8 * i))
proc sipHash24*(seed: StableHashSeed, data: openArray[byte]): uint64 =
  var v0 = 0x736f6d6570736575'u64 xor seed.k0; var v1 = 0x646f72616e646f6d'u64 xor seed.k1
  var v2 = 0x6c7967656e657261'u64 xor seed.k0; var v3 = 0x7465646279746573'u64 xor seed.k1
  var at = 0
  while at + 8 <= data.len:
    let m = little(data, at); v3 = v3 xor m; round(v0,v1,v2,v3); round(v0,v1,v2,v3); v0 = v0 xor m; at += 8
  var tail = uint64(data.len) shl 56
  for i in 0 ..< data.len - at: tail = tail or (uint64(data[at + i]) shl (8 * i))
  v3 = v3 xor tail; round(v0,v1,v2,v3); round(v0,v1,v2,v3); v0 = v0 xor tail; v2 = v2 xor 0xff
  for _ in 0 ..< 4: round(v0,v1,v2,v3)
  v0 xor v1 xor v2 xor v3
