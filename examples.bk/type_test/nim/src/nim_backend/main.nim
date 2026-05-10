import std/options
import ../../../../../src/nicp_cdk
import ../../../../../src/nicp_cdk/ic_types/ic_text
import ../../../../../src/nicp_cdk/ic_types/ic_record
import ../../../../../src/nicp_cdk/ic_types/candid_types
import ../../../../../src/nicp_cdk/ic_types/ic_principal
import ../../../../../src/nicp_cdk/ic_types/ic_func


proc responseNull() {.query.} =
  reply(nil)


proc responseEmpty() {.query.} =
  reply()


proc boolFunc() {.query.} =
  reply(true)


proc intFunc() {.query.} =
  reply(1)


proc int8Func() {.query.} =
  reply(1'i8)


proc int16Func() {.query.} =
  reply(1'i16)


proc int32Func() {.query.} =
  reply(1'i32)


proc int64Func() {.query.} =
  reply(1'i64)


proc natFunc() {.query.} =
  reply(1'u)


proc nat8Func() {.query.} =
  reply(1'u8)


proc nat16Func() {.query.} =
  reply(1'u16)


proc nat32Func() {.query.} =
  reply(1'u32)


proc nat64Func() {.query.} =
  reply(1'u64)


proc floatFunc() {.query.} =
  reply(1.0'f64)


proc textFunc() {.query.} =
  reply("Hello, World!")


proc blobFunc() {.query.} =
  let data = toBlob("Hello, World!")
  reply(data)


proc vecNatFunc() {.query.} =
  reply(@[1'u, 2'u, 3'u, 4'u, 5'u])


proc vecTextFunc() {.query.} =
  reply(@["Hello", "World", "Candid", "Vector"])


proc vecBoolFunc() {.query.} =
  reply(@[true, false, true, false])


proc vecIntFunc() {.query.} =
  reply(@[1, -2, 3, -4, 5])


proc vecVecNatFunc() {.query.} =
  let inner1 = @[1'u, 2'u]
  let inner2 = @[3'u, 4'u, 5'u]
  let outer = @[inner1, inner2]
  reply(outer)


proc vecVecTextFunc() {.query.} =
  let inner1 = @["Hello", "World"]
  let inner2 = @["Candid", "Vector"]
  let outer = @[inner1, inner2]
  reply(outer)


proc vecVecBoolFunc() {.query.} =
  let inner1 = @[true, false]
  let inner2 = @[false, true]
  let outer = @[inner1, inner2]
  reply(outer)


proc vecVecIntFunc() {.query.} =
  let inner1 = @[1, -2]
  let inner2 = @[3, -4, 5]
  let outer = @[inner1, inner2]
  reply(outer)


proc optTextSome() {.query.} =
  reply(some("Hello, Option!"))


proc optTextNone() {.query.} =
  reply(none(string))


proc optIntSome() {.query.} =
  reply(some(1))


proc optIntNone() {.query.} =
  reply(none(int))


proc optNatSome() {.query.} =
  reply(some(1'u))


proc optNatNone() {.query.} =
  reply(none(uint))


proc optFloatSome() {.query.} =
  reply(some(1.0'f64))


proc optFloatNone() {.query.} =
  reply(none(float64))


proc optBoolSome() {.query.} =
  reply(some(true))


proc optBoolNone() {.query.} =
  reply(none(bool))


# record: 単純なレコードを返す
proc recordSimple() {.query.} =
  let rec = %*{
    "name": "Alice",
    "age": 30
  }
  reply(rec)


# record: ネストしたレコードを返す
proc recordNested() {.query.} =
  let outer = %*{
    "user": %*{
      "id": 1'u,
      "active": true
    },
    "meta": %*{
      "note": "ok"
    }
  }
  reply(outer)


# =========================
# Variant (Enum) functions
# =========================
type Color* = enum
  Red
  Green
  Blue

# Color: 値なしvariant相当
proc variantColorRed() {.query.} =
  reply(Color.Red)

proc variantColorGreen() {.query.} =
  reply(Color.Green)

proc variantColorBlue() {.query.} =
  reply(Color.Blue)


# =========================
# Principal functions
# =========================

proc principalFunc() {.query.} =
  let principal = Principal.fromText("aaaaa-aa")
  reply(principal)

proc principalAnonymous() {.query.} =
  let principal = Principal.fromText("2vxsx-fae")
  reply(principal)

proc principalCanister() {.query.} =
  let principal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai")
  reply(principal)


# =========================
# Function reference tests
# =========================

proc greet() {.query.} =
  let request = Request.new()
  let msg = request.getStr(0)
  reply("Hello, " & msg & "!")

proc funcRefTextQuery() {.query.} =
  let selfPrincipal = Principal.fromText("ucwa4-rx777-77774-qaada-cai")
  # 自キャニスター上の "greet" を参照として返す
  let f = IcFunc.new(
    selfPrincipal,
    FuncType.Query,
    "greet",
    @[ctText],
    some(ctText),
    @[CandidTypeDesc(kind: ctText)],
    some(CandidTypeDesc(kind: ctText))
  )
  reply(f)
