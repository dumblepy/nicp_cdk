import std/asyncdispatch
import std/strutils
import ../../src/nicp_cdk
import ../../src/nicp_cdk/canisters/management_canister
import ../../src/nicp_cdk/ic_types/ic_principal


const
  VetKdContext = "vetkey_example_v1"
  VetKdKeyName = "test_key_1"
  VetKdSampleTransportPublicKeyHex = "a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d"


proc hexToBytes(value: string): seq[uint8] =
  var cleaned = value.strip().replace(" ", "").replace("\n", "").replace("\t", "")
  if cleaned.len >= 2 and cleaned[0] == '0' and (cleaned[1] == 'x' or cleaned[1] == 'X'):
    cleaned = cleaned[2..^1]
  if cleaned.len == 0:
    return @[]

  doAssert cleaned.len mod 2 == 0
  result = newSeq[uint8](cleaned.len div 2)
  for i in 0..<result.len:
    let start = i * 2
    result[i] = uint8(parseHexInt(cleaned[start ..< start + 2]))


proc toBytes(value: string): seq[uint8] =
  result = newSeq[uint8](value.len)
  for i, c in value:
    result[i] = uint8(ord(c))


proc callerInput(): seq[uint8] =
  let caller = Msg.caller()
  result = newSeq[uint8](caller.bytes.len)
  for i, b in caller.bytes:
    result[i] = uint8(b)


proc makeKeyId(): VetKdKeyId =
  VetKdKeyId(
    curve: VetKdCurve.bls12_381_g2,
    name: VetKdKeyName
  )


proc getPublicKeyArgs(): VetKdPublicKeyArgs =
  VetKdPublicKeyArgs(
    canister_id: none(Principal),
    context: VetKdContext.toBytes(),
    key_id: makeKeyId()
  )


proc makeDeriveArgs(transportPublicKey: seq[uint8]): VetKdDeriveKeyArgs =
  VetKdDeriveKeyArgs(
    input: callerInput(),
    context: VetKdContext.toBytes(),
    transport_public_key: transportPublicKey,
    key_id: makeKeyId()
  )


proc getPublicKey*() {.async.} =
  let publicKeyResult = await ManagementCanister.vetKdPublicKey(getPublicKeyArgs())
  reply(publicKeyResult.public_key)


proc deriveKey*() {.async.} =
  let transportPublicKey = VetKdSampleTransportPublicKeyHex.hexToBytes()
  let deriveResult = await ManagementCanister.vetKdDeriveKey(makeDeriveArgs(transportPublicKey))
  reply(deriveResult.encrypted_key)


proc deriveKeyWithTransportPublicKey*() {.async.} =
  let request = Request.new()
  let transportPublicKey = request.getBlob(0)
  let deriveResult = await ManagementCanister.vetKdDeriveKey(makeDeriveArgs(transportPublicKey))
  reply(deriveResult.encrypted_key)
