import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/storage/stable_value
import ../../../../src/nicp_cdk/storage/stable_seq
import ../../../../src/nicp_cdk/storage/stable_btree
import ../../../../src/nicp_cdk/storage/memory_view

# Define base offsets for each storage structure to avoid collision
const
  IntDbOffset = 0'u64
  UintDbOffset = 100000'u64
  StringDbOffset = 200000'u64
  PrincipalDbOffset = 300000'u64
  BoolDbOffset = 400000'u64
  FloatDbOffset = 500000'u64
  DoubleDbOffset = 600000'u64
  CharDbOffset = 700000'u64
  ByteDbOffset = 800000'u64
  SeqIntDbOffset = 900000'u64
  BTreeDbOffset = 2000000'u64
  BTreeDbLimit = 1000000'u64

# ==================================================
# int
# ==================================================
var intDb = initIcStableValue(int, IntDbOffset)

proc int_set() {.update.} =
  let request = Request.new()
  let value = request.getInt(0)
  intDb.set(value)
  reply()

proc int_get() {.query.} =
  let value = intDb.get()
  reply(value)

# ==================================================
# uint
# ==================================================
var uintDb = initIcStableValue(uint, UintDbOffset)

proc uint_set() {.update.} =
  let request = Request.new()
  let value = request.getNat(0)
  uintDb.set(value)
  reply()

proc uint_get() {.query.} =
  let value = uintDb.get()
  reply(value)

# ==================================================
# string
# ==================================================
var stringDb = initIcStableValue(string, StringDbOffset)

proc string_set() {.update.} =
  let request = Request.new()
  let value = request.getStr(0)
  stringDb.set(value)
  reply()

proc string_get() {.query.} =
  let value = stringDb.get()
  reply(value)

 
# ==================================================
# principal
# ==================================================
var principalDb = initIcStableValue(Principal, PrincipalDbOffset)

proc principal_set() {.update.} =
  let request = Request.new()
  let value = request.getPrincipal(0)
  principalDb.set(value)
  reply()

proc principal_get() {.query.} =
  let value = principalDb.get()
  reply(value)

 
# ==================================================
# bool
# ==================================================
var boolDb = initIcStableValue(bool, BoolDbOffset)

proc bool_set() {.update.} =
  let request = Request.new()
  let value = request.getBool(0)
  boolDb.set(value)
  reply()

proc bool_get() {.query.} =
  let value = boolDb.get()
  reply(value)

 
# ==================================================
# float
# ==================================================
var floatDb = initIcStableValue(float32, FloatDbOffset)

proc float_set() {.update.} =
  let request = Request.new()
  let value = request.getFloat32(0)
  floatDb.set(value)
  reply()

proc float_get() {.query.} =
  let value = floatDb.get()
  reply(value)

 
# ==================================================
# double
# ==================================================
var doubleDb = initIcStableValue(float64, DoubleDbOffset)

proc double_set() {.update.} =
  let request = Request.new()
  let value = request.getFloat64(0)
  doubleDb.set(value)
  reply()

proc double_get() {.query.} =
  let value = doubleDb.get()
  reply(value)

 
# ==================================================
# char
# ==================================================
var charDb = initIcStableValue(char, CharDbOffset)

proc char_set() {.update.} =
  let request = Request.new()
  let value = request.getNat8(0)
  charDb.set(char(value))
  reply()

proc char_get() {.query.} =
  let value = charDb.get()
  reply(uint8(ord(value)))

 
# ==================================================
# byte
# ==================================================
var byteDb = initIcStableValue(byte, ByteDbOffset)

proc byte_set() {.update.} =
  let request = Request.new()
  let value = request.getNat8(0)
  byteDb.set(value)
  reply()

proc byte_get() {.query.} =
  let value = byteDb.get()
  reply(value)


# ==================================================
# seq[int]
# ==================================================
var seqIntDb = initIcStableSeq[int](SeqIntDbOffset)

proc seqInt_reset() {.update.} =
  seqIntDb.clear()
  reply()

proc seqInt_set() {.update.} =
  let request = Request.new()
  let value = request.getInt(0)
  seqIntDb.add(value)
  reply(value)

proc seqInt_get() {.query.} =
  let request = Request.new()
  let index = request.getNat(0)
  let value = seqIntDb[int(index)]
  reply(value)

proc seqInt_len() {.query.} =
  reply(uint(seqIntDb.len()))

proc seqInt_setAt() {.update.} =
  let request = Request.new()
  let index = request.getNat(0)
  let value = request.getInt(1)
  seqIntDb[int(index)] = value
  reply()

proc seqInt_delete() {.update.} =
  let request = Request.new()
  let index = request.getNat(0)
  seqIntDb.delete(int(index))
  reply()

proc seqInt_values() {.query.} =
  reply(seqIntDb.toSeq())

# ==================================================
# IcStableTable[string, string] (B+Tree implementation)
# ==================================================
# This map keeps its searchable index in stable memory.  The bounded view
# isolates it from the legacy stable values/tables above, while `range` shows
# the key-order traversal provided by the B+Tree backend.
type BTreeEntry = object
  key: string
  value: string

var btreeDb = initIcStableTable[string, string](
  initRawMemoryView(BTreeDbOffset, BTreeDbLimit)
)

proc btree_reset() {.update.} =
  btreeDb.clear()
  reply()

proc btree_set() {.update.} =
  try:
    icEcho("btree_set: begin")
    let request = Request.new()
    icEcho("btree_set: request decoded")
    let key = request.getStr(0)
    let value = request.getStr(1)
    icEcho("btree_set: writing key=", key)
    btreeDb[key] = value
    icEcho("btree_set: write complete")
    reply()
    icEcho("btree_set: reply sent")
  except Exception as e:
    ## The runtime reports uncaught Nim exceptions as a generic IC trap. Keep
    ## the concrete reason in canister logs for malformed requests or a
    ## corrupted/overlapping stable-memory region.
    icEcho("btree_set failed: ", e.msg)
    raise

proc btree_get() {.query.} =
  let request = Request.new()
  let key = request.getStr(0)
  reply(btreeDb[key])

proc btree_hasKey() {.query.} =
  let request = Request.new()
  reply(btreeDb.hasKey(request.getStr(0)))

proc btree_len() {.query.} =
  reply(uint(btreeDb.len()))

proc btree_range() {.query.} =
  ## Returns entries in ascending key order for the half-open interval
  ## `[startKey, endKey)`.
  let request = Request.new()
  let startKey = request.getStr(0)
  let endKey = request.getStr(1)
  var entries: seq[BTreeEntry] = @[]
  for key, value in btreeDb.range(startKey, endKey):
    entries.add(BTreeEntry(key: key, value: value))
  reply(entries)
