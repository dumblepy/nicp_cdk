import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/storage/stable_value
import ../../../../src/nicp_cdk/storage/stable_seq
import ../../../../src/nicp_cdk/storage/stable_table
import ../../../../src/nicp_cdk/storage/stable_hash_map

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
  HashDbOffset = 3000000'u64
  HashDbLimit = 1000000'u64

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
# IcStableHashMap[string, string]
# ==================================================
var hashDb = initIcStableHashMap[string, string](
  initRawMemoryView(HashDbOffset, HashDbLimit)
)

proc hash_reset() {.update.} =
  hashDb.clear()
  reply()

proc hash_set() {.update.} =
  let request = Request.new()
  hashDb[request.getStr(0)] = request.getStr(1)
  reply()

proc hash_get() {.query.} =
  let request = Request.new()
  reply(hashDb[request.getStr(0)])

proc hash_hasKey() {.query.} =
  let request = Request.new()
  reply(hashDb.hasKey(request.getStr(0)))

proc hash_len() {.query.} =
  reply(uint(hashDb.len()))

# ==================================================
# IcStableTable[string, string] (B+Tree implementation)
# ==================================================
# This map keeps its searchable index in stable memory, while `range` shows
# the key-order traversal provided by the B+Tree backend.
type TableEntry = object
  key: string
  value: string

var tableDb = initIcStableTable[string, string](
  initRawMemoryView(BTreeDbOffset, BTreeDbLimit)
)

proc table_reset() {.update.} =
  tableDb.clear()
  reply()

proc table_set() {.update.} =
  try:
    icEcho("table_set: begin")
    let request = Request.new()
    icEcho("table_set: request decoded")
    let key = request.getStr(0)
    let value = request.getStr(1)
    icEcho("table_set: writing key=", key)
    tableDb[key] = value
    icEcho("table_set: write complete")
    reply()
    icEcho("table_set: reply sent")
  except Exception as e:
    ## The runtime reports uncaught Nim exceptions as a generic IC trap. Keep
    ## the concrete reason in canister logs for malformed requests or a
    ## corrupted/overlapping stable-memory region.
    icEcho("table_set failed: ", e.msg)
    raise

proc table_get() {.query.} =
  let request = Request.new()
  let key = request.getStr(0)
  reply(tableDb[key])

proc table_hasKey() {.query.} =
  let request = Request.new()
  reply(tableDb.hasKey(request.getStr(0)))

proc table_len() {.query.} =
  reply(uint(tableDb.len()))

proc table_range() {.query.} =
  ## Returns entries in ascending key order for the half-open interval
  ## `[startKey, endKey)`.
  let request = Request.new()
  let startKey = request.getStr(0)
  let endKey = request.getStr(1)
  var entries: seq[TableEntry] = @[]
  for key, value in tableDb.range(startKey, endKey):
    entries.add(TableEntry(key: key, value: value))
  reply(entries)
