import std/strutils
import std/options
import std/tables
import std/sequtils  # mapItのために追加
import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/ic_types/candid_types
import ../../../../src/nicp_cdk/ic_types/candid_message/candid_encode
import ../../../../src/nicp_cdk/ic_types/candid_funcs
import ../../../../src/nicp_cdk/ic_types/ic_record
import ../../../../src/nicp_cdk/ic0/ic0

type
  SimpleStatus* {.pure.} = enum
    Active = 0
    Inactive = 1

  Priority* {.pure.} = enum
    Low = 0
    Medium = 1
    High = 2
    Critical = 3


proc nullResponse() {.query.} =
  reply(nil)

proc emptyResponse() {.query.} =
  reply()

proc boolArg() {.query.} =
  let request = Request.new()
  let arg = request.getBool(0)
  icEcho "arg: ", arg
  reply(arg)

proc intArg() {.query.} =
  let request = Request.new()
  let arg = request.getInt(0)
  icEcho "arg: ", arg
  reply(arg)

proc int8Arg() {.query.} =
  let request = Request.new()
  let arg = request.getInt8(0)
  icEcho "arg: ", arg
  reply(arg)

proc int16Arg() {.query.} =
  let request = Request.new()
  let arg = request.getInt16(0)
  icEcho "arg: ", arg
  reply(arg)

proc int32Arg() {.query.} =
  let request = Request.new()
  let arg = request.getInt32(0)
  icEcho "arg: ", arg
  reply(arg)

proc int64Arg() {.query.} =
  let request = Request.new()
  let arg = request.getInt64(0)
  icEcho "arg: ", arg
  reply(arg)

proc natArg() {.query.} =
  let request = Request.new()
  let arg = request.getNat(0)
  icEcho "arg: ", arg
  reply(arg)

proc nat8Arg() {.query.} =
  let request = Request.new()
  let arg = request.getNat8(0)
  reply(arg)

proc nat16Arg() {.query.} =
  let request = Request.new()
  let arg = request.getNat16(0)
  icEcho "arg: ", arg
  reply(arg)

proc nat32Arg() {.query.} =
  let request = Request.new()
  let arg = request.getNat32(0)
  icEcho "arg: ", arg
  reply(arg)

proc nat64Arg() {.query.} =
  let request = Request.new()
  let arg = request.getNat64(0)
  icEcho "arg: ", arg
  reply(arg)

proc floatArg() {.query.} =
  let request = Request.new()
  let arg = request.getFloat(0)
  icEcho "arg: ", arg
  reply(arg)

proc float32Arg() {.query.} =
  let request = Request.new()
  let arg = request.getFloat32(0)
  icEcho "arg: ", arg
  reply(arg)

proc float64Arg() {.query.} =
  let request = Request.new()
  let arg = request.getFloat64(0)
  icEcho "arg: ", arg
  reply(arg)

proc textArg() {.query.} =
  let request = Request.new()
  let arg = request.getStr(0)
  icEcho "arg: ", arg
  reply(arg)

proc blobArg() {.query.} =
  let request = Request.new()
  let arg = request.getBlob(0)
  icEcho "arg length: ", arg.len
  icEcho "arg: ", arg
  reply(arg)

proc optArg() {.query.} =
  let request = Request.new()
  # Option[uint8]として受け取る例
  let arg = request.getOpt(0)
  icEcho "arg isSome: ", arg.isSome()
  if arg.isSome():
    icEcho "arg value: ", $arg.get().getNat8()
  reply(arg)

proc vecArg() {.query.} =
  let request = Request.new()
  let arg = request.getVec(0)
  let typedArg = arg.map(proc(val: CandidValue): uint16 = val.getNat16())
  icEcho "arg length: ", typedArg.len
  icEcho "arg: ", $typedArg
  reply(typedArg)

proc variantArg() {.query.} =
  let request = Request.new()
  let arg = request.getVariant(0)
  icEcho "arg tag: ", arg.tag
  icEcho "arg value: ", arg.value
  reply(arg)

proc funcArg() {.query.} =
  let request = Request.new()
  let arg = request.getFunc(0)
  icEcho "arg principal: ", arg.principal
  icEcho "arg method: ", arg.methodName
  reply(arg)

proc recordArg() {.query.} =
  let request = Request.new()
  let arg = request.getRecord(0)
  icEcho "arg name: ", arg["name"].getStr()
  icEcho "arg age: ", $arg["age"].getNat()
  icEcho "arg isActive: ", $arg["isActive"].getBool()
  let response = %*{
    "name": arg["name"].getStr(),
    "age": arg["age"].getNat(),
    "isActive": arg["isActive"].getBool()
  }
  reply(response)



# proc msgPrincipal() {.query.} =
#   let caller = Msg.caller()
#   reply(caller)

# proc responseEmpty() {.query.} =
#   reply()

# proc responseRecord() {.query.} =
#   let record = %*{
#     "name": "John",
#     "age": 30,
#     "isActive": true
#   }
#   echo "record: ", $record
#   reply(record)

# proc responsePrincipal() {.query.} =

#   echo "===== main.nim responsePrincipal() ====="
#   let caller = Msg.caller()
#   icEcho "caller: ", caller
#   reply(caller)


# proc responseBlob() {.query.} =
#   echo "===== main.nim responseBlob() ====="
#   # テスト用のblobデータを返す（"Hello World"のUTF-8バイト列）
#   let blobData = @[0x48u8, 0x65u8, 0x6Cu8, 0x6Cu8, 0x6Fu8, 0x20u8, 0x57u8, 0x6Fu8, 0x72u8, 0x6Cu8, 0x64u8]
#   icEcho "response blob length: ", blobData.len
#   reply(blobData)


# proc responseOpt() {.query.} =
#   echo "===== main.nim responseOpt() ====="
#   # テスト用のOptionデータを返す（Some(42)）
#   let optData = some(uint8(42))
#   icEcho "response opt isSome: ", optData.isSome()
#   if optData.isSome():
#     icEcho "response opt value: ", optData.get()
#   reply(optData)


# proc responseVec() {.query.} =
#   echo "===== main.nim responseVec() ====="
#   # テスト用のVectorデータを返す（[100, 200, 300]のnat16）
#   let vecData = @[
#     newCandidValue(uint16(100)),
#     newCandidValue(uint16(200)),
#     newCandidValue(uint16(300))
#   ]
#   icEcho "response vec length: ", vecData.len
#   reply(vecData)


# proc responseVariant() {.query.} =
#   echo "===== main.nim responseVariant() ====="
#   # テスト用のVariantデータを返す（success variant with text）
#   let variantData = CandidVariant(
#     tag: candidHash("success"),
#     value: newCandidText("Operation completed successfully")
#   )
#   icEcho "response variant tag: ", variantData.tag
#   icEcho "response variant value: ", variantData.value
#   reply(variantData)


# proc responseNestedRecord() {.query.} =
#   echo "===== main.nim responseNestedRecord() START ====="
  
#   try:
#     # シンプルなRecord構造で確実に動作させる（ネストなし）
#     echo "Step 1: Creating simple record structure..."
    
#     var record = newCRecord()
#     record["name"] = ic_record.newCText("Alice")
#     record["age"] = newCInt(30)
#     record["isActive"] = newCBool(true)
#     echo "Step 2: Simple record created"
    
#     echo "Step 3: About to call reply function..."
#     reply(record)
#     echo "Step 4: Reply successful"
    
#   except CatchableError as e:
#     echo "Error at step: ", e.msg
#     echo "Error type: ", $e.name
#     reply("Detailed error: " & e.msg & " (Type: " & $e.name & ")")
  
#   echo "===== main.nim responseNestedRecord() END ====="


# proc argSimpleStatus*() {.query.} =
#   echo "===== main.nim argSimpleStatus() ====="
#   let request = Request.new()
#   let arg = request.getEnum(0, SimpleStatus)
#   icEcho "SimpleStatus arg: ", arg
#   reply(arg)

# proc responseSimpleStatus*() {.query.} =
#   echo "===== main.nim responseSimpleStatus() ====="
#   let status = SimpleStatus.Active
#   icEcho "SimpleStatus response: ", status
#   reply(status)

# proc argPriority*() {.query.} =
#   echo "===== main.nim argPriority() ====="
#   let request = Request.new()
#   let arg = request.getEnum(0, Priority)
#   icEcho "Priority arg: ", arg
#   reply(arg)

# proc responsePriority*() {.query.} =
#   echo "===== main.nim responsePriority() ====="
#   let priority = Priority.High
#   icEcho "Priority response: ", priority
#   reply(priority)

# # ================================================================================
# # Phase 3.1: Record内Enum値のCanister関数
# # ================================================================================

# proc argRecordWithEnum*() {.query.} =
#   echo "===== main.nim argRecordWithEnum() ====="
#   let request = Request.new()
#   let recordArg = request.getVariant(0)
  
#   # Record内のEnum値を取得（簡易バージョン）
#   icEcho "Record variant tag: ", recordArg.tag
#   icEcho "Record variant value: ", recordArg.value
  
#   # 受け取ったVariantをそのまま返す
#   reply(recordArg)

# proc responseRecordWithEnum*() {.query.} =
#   echo "===== main.nim responseRecordWithEnum() ====="
  
#   # 一時的にシンプルなレスポンス
#   let recordResponse = "Record with enum response temporarily disabled"
  
#   icEcho "Record with enum response: ", recordResponse
#   reply(recordResponse)