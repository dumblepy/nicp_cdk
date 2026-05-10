import std/tables
import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/storage/stable_value
import ../../../../src/nicp_cdk/storage/stable_seq
import ../../../../src/nicp_cdk/storage/stable_table

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
  TableDbOffset = 2000000'u64
  ObjectDbOffset = 3000000'u64

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
# Table[principal, string]
# ==================================================
var tableDb = initIcStableTable[Principal, string](TableDbOffset)

proc table_reset() {.update.} =
  tableDb.clear()
  reply()

proc table_set() {.update.} =
  let principal = Msg.caller()
  let request = Request.new()
  let message = request.getStr(0)
  tableDb[principal] = message
  reply()

proc table_get() {.query.} =
  let principal = Msg.caller()
  let value = tableDb[principal]
  reply(value)

proc table_len() {.query.} =
  reply(uint(tableDb.len()))

proc table_hasKey() {.query.} =
  let principal = Msg.caller()
  reply(tableDb.hasKey(principal))

proc table_setFor() {.update.} =
  let request = Request.new()
  let principal = request.getPrincipal(0)
  let message = request.getStr(1)
  tableDb[principal] = message
  reply()

proc table_getFor() {.query.} =
  let request = Request.new()
  let principal = request.getPrincipal(0)
  let value = tableDb[principal]
  reply(value)

proc table_keys() {.query.} =
  var keys: seq[Principal] = @[]
  for key in tableDb.keys():
    keys.add(key)
  reply(keys)

proc table_values() {.query.} =
  var values: seq[string] = @[]
  for value in tableDb.values():
    values.add(value)
  reply(values)

# ==================================================
# object
# ==================================================
type UserProfile = object
  id: uint
  name: string
  active: bool

var objectDb = initIcStableTable[Principal, UserProfile](ObjectDbOffset)

proc object_set() {.update.} =
  try:
    let principal = Msg.caller()
    let request = Request.new()
    let id = request.getNat(0)
    let name = request.getStr(1)
    let active = request.getBool(2)
    objectDb[principal] = UserProfile(id: id, name: name, active: active)
    reply()
  except Exception as e:
    echo "Error: ", e.msg
    reply(e.msg)

proc object_get() {.query.} =
  let principal = Msg.caller()
  let value = objectDb[principal]
  reply(value)
