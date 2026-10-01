import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/storage/memory_manager
import ../../../../src/nicp_cdk/storage/stable_value
import ../../../../src/nicp_cdk/storage/stable_seq
import ../../../../src/nicp_cdk/storage/stable_table
import ../../../../src/nicp_cdk/storage/stable_hash_map

# Stable memory is partitioned by MemoryId. These ids are part of the
# application's stable schema: never reuse or renumber them after a deployment,
# otherwise a structure would silently open another structure's region.
const
  IntMemoryId = newMemoryId(32)
  UintMemoryId = newMemoryId(33)
  StringMemoryId = newMemoryId(34)
  PrincipalMemoryId = newMemoryId(35)
  BoolMemoryId = newMemoryId(36)
  FloatMemoryId = newMemoryId(37)
  DoubleMemoryId = newMemoryId(38)
  CharMemoryId = newMemoryId(39)
  ByteMemoryId = newMemoryId(40)
  SeqIntMemoryId = newMemoryId(41)
  BTreeMemoryId = newMemoryId(42)
  HashMemoryId = newMemoryId(43)

# This CDK has no implicit lifecycle dispatch, so the example exports the IC
# `canister_init` / `canister_post_upgrade` entry points explicitly and opens
# stable storage there. Module-init code must not touch stable memory: it runs
# during WASM instantiation, where the manager is not available yet.
var manager: MemoryManager

# ==================================================
# int
# ==================================================
var intDb: StableValue[int]

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
var uintDb: StableValue[uint]

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
var stringDb: StableValue[string]

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
var principalDb: StableValue[Principal]

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
var boolDb: StableValue[bool]

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
var floatDb: StableValue[float32]

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
var doubleDb: StableValue[float64]

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
var charDb: StableValue[char]

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
var byteDb: StableValue[byte]

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
var seqIntDb: IcStableSeq[int]

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
var hashDb: IcStableHashMap[string, string]

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

var tableDb: IcStableTable[string, string]

proc openStorage(fresh: bool) =
  ## Opens every stable structure on the manager. `fresh` is true only for
  ## `canister_init`; `canister_post_upgrade` must reopen, never create.
  ##
  ## The application links the WASI polyfill, which owns an `MGR` prefix at
  ## offset 0, so the application manager is placed after it.
  let backend = newIcOffsetBackend(newIcStableBackend())
  manager =
    if fresh:
      createMemoryManagerStrict(backend)
    else:
      openExistingMemoryManagerStrict(backend)

  intDb = initStableValue[int](manager.getMemory(IntMemoryId))
  uintDb = initStableValue[uint](manager.getMemory(UintMemoryId))
  stringDb = initStableValue[string](manager.getMemory(StringMemoryId))
  principalDb = initStableValue[Principal](manager.getMemory(PrincipalMemoryId))
  boolDb = initStableValue[bool](manager.getMemory(BoolMemoryId))
  floatDb = initStableValue[float32](manager.getMemory(FloatMemoryId))
  doubleDb = initStableValue[float64](manager.getMemory(DoubleMemoryId))
  charDb = initStableValue[char](manager.getMemory(CharMemoryId))
  byteDb = initStableValue[byte](manager.getMemory(ByteMemoryId))
  seqIntDb = initIcStableSeq[int](manager.getMemory(SeqIntMemoryId))
  hashDb = initIcStableHashMap[string, string](manager.getMemory(HashMemoryId))
  tableDb = initIcStableTable[string, string](manager.getMemory(BTreeMemoryId))

proc canister_init() {.exportwasm.} =
  openStorage(fresh = true)

proc canister_post_upgrade() {.exportwasm.} =
  openStorage(fresh = false)

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
