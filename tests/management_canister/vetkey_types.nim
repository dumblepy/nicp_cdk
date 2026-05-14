import std/options
import std/tables
import ../../src/nicp_cdk/ic_types/candid_types
import ../../src/nicp_cdk/ic_types/ic_principal
import ../../src/nicp_cdk/ic_types/ic_record
import ../../src/nicp_cdk/ic_types/candid_message/candid_message_types

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


proc candidValueToVetKdPublicKeyResult*(candidValue: CandidValue): VetKdPublicKeyResult =
  if candidValue.kind != ctRecord:
    raise newException(CandidDecodeError, "Expected record type for VetKdPublicKeyResult")

  let recordVal = candidValueToCandidRecord(candidValue)
  result = VetKdPublicKeyResult(
    public_key: recordVal["public_key"].getBlob()
  )


proc candidValueToVetKdDeriveKeyResult*(candidValue: CandidValue): VetKdDeriveKeyResult =
  if candidValue.kind != ctRecord:
    raise newException(CandidDecodeError, "Expected record type for VetKdDeriveKeyResult")

  let recordVal = candidValueToCandidRecord(candidValue)
  result = VetKdDeriveKeyResult(
    encrypted_key: recordVal["encrypted_key"].getBlob()
  )
