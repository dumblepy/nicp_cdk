import std/options
import std/asyncfutures
import std/asyncdispatch
import std/tables
import std/strutils
import ../../ic0/ic0
import ../../ic_types/candid_types
import ../../ic_types/ic_principal
import ../../ic_types/ic_record
import ../../ic_types/candid_message/candid_encode
import ../../ic_types/candid_message/candid_decode
import ../../ic_types/candid_message/candid_message_types
import ../../ic_api
import ./estimateGas
import ./management_canister_type


# ================================================================================
# Utilities
# ================================================================================
proc getRejectDetail(): string =
  ## ic0 の reject 情報を code / message 付きで取得する
  try:
    let code = ic0_msg_reject_code()
    let size = ic0_msg_reject_msg_size()
    var text = ""
    if size > 0:
      var buf = newSeq[uint8](size)
      ic0_msg_reject_msg_copy(ptrToInt(addr buf[0]), 0, size)
      text = newString(size)
      for i in 0..<size:
        text[i] = char(buf[i])
    else:
      text = "<empty>"
    return " (code=" & $code & ", message=" & text & ")"
  except Exception as e:
    return " (reject detail unavailable: " & e.msg & ")"


proc encodeCallArg(arg: CandidValue): seq[uint8] =
  encodeCandidMessage(@[arg])


# ================================================================================
# vetKD related type definitions
# ================================================================================
type
  VetKdCurve* {.pure.} = enum
    bls12_381_g2 = 0

  VetKdKeyId* = object
    curve*: VetKdCurve
    name*: string

  VetKdPublicKeyArgs* = object
    canister_id*: Option[Principal]
    context*: seq[uint8]
    key_id*: VetKdKeyId

  VetKdPublicKeyResult* = object
    public_key*: seq[uint8]

  VetKdDeriveKeyArgs* = object
    input*: seq[uint8]
    context*: seq[uint8]
    transport_public_key*: seq[uint8]
    key_id*: VetKdKeyId

  VetKdDeriveKeyResult* = object
    encrypted_key*: seq[uint8]


# ================================================================================
# Constants
# ================================================================================
const
  VetKdTestKey1Cycles = 10_000_000_000'u64
  VetKdKey1Cycles = 26_000_000_000'u64


# ================================================================================
# Candid conversions
# ================================================================================
proc `%`*(keyId: VetKdKeyId): CandidRecord =
  result = CandidRecord(
    kind: ckRecord,
    fields: initOrderedTable[string, CandidValue]()
  )
  result.fields["curve"] = newCandidValue(keyId.curve)
  result.fields["name"] = newCandidText(keyId.name)


proc `%`*(arg: VetKdPublicKeyArgs): CandidRecord =
  result = CandidRecord(
    kind: ckRecord,
    fields: initOrderedTable[string, CandidValue]()
  )
  if arg.canister_id.isSome:
    result.fields["canister_id"] = newCandidOptWithInnerType(
      ctPrincipal,
      some(newCandidPrincipal(arg.canister_id.get))
    )
  else:
    result.fields["canister_id"] = newCandidOptWithInnerType(ctPrincipal, none(CandidValue))
  result.fields["context"] = newCandidBlob(arg.context)
  result.fields["key_id"] = recordToCandidValue(%arg.key_id)


proc `%`*(arg: VetKdDeriveKeyArgs): CandidRecord =
  result = CandidRecord(
    kind: ckRecord,
    fields: initOrderedTable[string, CandidValue]()
  )
  result.fields["input"] = newCandidBlob(arg.input)
  result.fields["context"] = newCandidBlob(arg.context)
  result.fields["transport_public_key"] = newCandidBlob(arg.transport_public_key)
  result.fields["key_id"] = recordToCandidValue(%arg.key_id)


proc candidValueToVetKdPublicKeyResult(candidValue: CandidValue): VetKdPublicKeyResult =
  if candidValue.kind != ctRecord:
    raise newException(CandidDecodeError, "Expected record type for VetKdPublicKeyResult")

  let recordVal = candidValueToCandidRecord(candidValue)
  return VetKdPublicKeyResult(
    public_key: recordVal["public_key"].getBlob()
  )


proc candidValueToVetKdDeriveKeyResult(candidValue: CandidValue): VetKdDeriveKeyResult =
  if candidValue.kind != ctRecord:
    raise newException(CandidDecodeError, "Expected record type for VetKdDeriveKeyResult")

  let recordVal = candidValueToCandidRecord(candidValue)
  return VetKdDeriveKeyResult(
    encrypted_key: recordVal["encrypted_key"].getBlob()
  )


# ================================================================================
# Callback helpers
# ================================================================================
proc onVetKdPublicKeySuccess(env: uint32) {.exportc.} =
  let fut = cast[Future[VetKdPublicKeyResult]](env)
  if fut == nil or fut.finished:
    return

  try:
    let size = ic0_msg_arg_data_size()
    var buf = newSeq[uint8](size)
    ic0_msg_arg_data_copy(ptrToInt(addr buf[0]), 0, size)
    let decoded = decodeCandidMessage(buf)
    complete(fut, candidValueToVetKdPublicKeyResult(decoded.values[0]))
  except Exception as e:
    fail(fut, e)


proc onVetKdDeriveKeySuccess(env: uint32) {.exportc.} =
  let fut = cast[Future[VetKdDeriveKeyResult]](env)
  if fut == nil or fut.finished:
    return

  try:
    let size = ic0_msg_arg_data_size()
    var buf = newSeq[uint8](size)
    ic0_msg_arg_data_copy(ptrToInt(addr buf[0]), 0, size)
    let decoded = decodeCandidMessage(buf)
    complete(fut, candidValueToVetKdDeriveKeyResult(decoded.values[0]))
  except Exception as e:
    fail(fut, e)


proc onVetKdPublicKeyReject(env: uint32) {.exportc.} =
  let fut = cast[Future[VetKdPublicKeyResult]](env)
  if fut == nil or fut.finished:
    return
  let msg = "vetkd_public_key call was rejected by the management canister" & getRejectDetail()
  fail(fut, newException(ValueError, msg))


proc onVetKdDeriveKeyReject(env: uint32) {.exportc.} =
  let fut = cast[Future[VetKdDeriveKeyResult]](env)
  if fut == nil or fut.finished:
    return
  let msg = "vetkd_derive_key call was rejected by the management canister" & getRejectDetail()
  fail(fut, newException(ValueError, msg))


# ================================================================================
# Cycle estimation
# ================================================================================
proc estimateVetKdDeriveKeyFallback(keyId: VetKdKeyId): uint64 =
  let baseCost =
    if keyId.name == "test_key_1":
      VetKdTestKey1Cycles
    else:
      VetKdKey1Cycles
  addMargin20(baseCost)


when defined(release):
  proc isReplicatedExecution(): bool =
    try:
      ic0_in_replicated_execution() == 1
    except:
      false

  proc estimateVetKdDeriveKeyDynamic(keyId: VetKdKeyId, payload: seq[uint8]): Option[uint64] =
    try:
      if payload.len == 0:
        return none(uint64)

      let curveValue = uint32(keyId.curve.ord)
      var costBuffer: array[16, uint8]
      let apiResult = ic0_cost_vetkd_derive_encrypted_key(
        ptrToInt(addr payload[0]),
        payload.len,
        curveValue,
        ptrToInt(addr costBuffer[0])
      )

      if apiResult != 0:
        return none(uint64)

      let exactCost = costBufferToUint64(costBuffer)
      if exactCost == 0:
        return none(uint64)

      return some(addMargin20(exactCost))
    except:
      return none(uint64)


proc estimateVetKdDeriveKey*(keyId: VetKdKeyId, payload: seq[uint8]): uint64 =
  when defined(enableVetKdDynamicCost) and defined(release):
    if isReplicatedExecution():
      let dynamicCost = estimateVetKdDeriveKeyDynamic(keyId, payload)
      if dynamicCost.isSome:
        return dynamicCost.get

  estimateVetKdDeriveKeyFallback(keyId)


# ================================================================================
# Management Canister API
# ================================================================================
proc vetKdPublicKey*(_: type ManagementCanister, arg: VetKdPublicKeyArgs): Future[VetKdPublicKeyResult] =
  result = newFuture[VetKdPublicKeyResult]("vetKdPublicKey")

  let mgmtPrincipalBytes: seq[uint8] = @[]
  let destPtr = if mgmtPrincipalBytes.len > 0: mgmtPrincipalBytes[0].addr else: nil
  let destLen = mgmtPrincipalBytes.len

  let methodName = "vetkd_public_key".cstring
  ic0_call_new(
    callee_src = cast[int](destPtr),
    callee_size = destLen,
    name_src = cast[int](methodName),
    name_size = methodName.len,
    reply_fun = cast[int](onVetKdPublicKeySuccess),
    reply_env = cast[int](result),
    reject_fun = cast[int](onVetKdPublicKeyReject),
    reject_env = cast[int](result)
  )

  try:
    let encoded = encodeCallArg(recordToCandidValue(%arg))
    ic0_call_data_append(ptrToInt(addr encoded[0]), encoded.len)
    let err = ic0_call_perform()
    if err != 0:
      fail(result, newException(ValueError, "call_perform failed with error: " & $err))
      return
  except Exception as e:
    fail(result, e)
    return


proc vetKdDeriveKey*(_: type ManagementCanister, arg: VetKdDeriveKeyArgs): Future[VetKdDeriveKeyResult] =
  result = newFuture[VetKdDeriveKeyResult]("vetKdDeriveKey")

  let mgmtPrincipalBytes: seq[uint8] = @[]
  let destPtr = if mgmtPrincipalBytes.len > 0: mgmtPrincipalBytes[0].addr else: nil
  let destLen = mgmtPrincipalBytes.len

  let methodName = "vetkd_derive_key".cstring
  ic0_call_new(
    callee_src = cast[int](destPtr),
    callee_size = destLen,
    name_src = cast[int](methodName),
    name_size = methodName.len,
    reply_fun = cast[int](onVetKdDeriveKeySuccess),
    reply_env = cast[int](result),
    reject_fun = cast[int](onVetKdDeriveKeyReject),
    reject_env = cast[int](result)
  )

  try:
    let candidArg = recordToCandidValue(%arg)
    let encoded = encodeCallArg(candidArg)
    let requiredCycles = estimateVetKdDeriveKey(arg.key_id, encoded)
    devEcho "Adding cycles for vetkd_derive_key: ", requiredCycles
    ic0_call_cycles_add128(0, requiredCycles)
    ic0_call_data_append(ptrToInt(addr encoded[0]), encoded.len)
    let err = ic0_call_perform()
    if err != 0:
      fail(result, newException(ValueError, "call_perform failed with error: " & $err))
      return
  except Exception as e:
    fail(result, e)
    return
