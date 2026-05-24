import std/asyncdispatch
import std/options
import std/strutils
import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/algorithm/hex_bytes
import ../../../../src/nicp_cdk/canisters/management_canister
import ../../../../src/nicp_cdk/ic_types/ic_principal

## Private KV / vetKD まわりのデバッグは `icEcho`（`ic0_debug_print`）を使用。
## ローカル `icp` では例: `examples/vetkey/.icp/cache/networks/local/network-launcher/stdout.log`


const
  ## `icp` の managed ローカルレプリカは vetKD しきい値として **`key_1`** のみ公開する（`test_key_1` は無い）。
  ## dfx の一部環境では `test_key_1` がある場合があるため、レプリカのエラーに従って切り替えること。
  VetKdKeyName = "key_1"


type
  PrivateKvEnvelope = object
    owner: Principal
    key_version: uint
    context_label: string
    input_label: string
    public_key_hex: string
    encrypted_key_hex: string


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


proc appendU32Be(result: var seq[uint8], value: uint32) =
  result.add uint8((value shr 24) and 0xFF)
  result.add uint8((value shr 16) and 0xFF)
  result.add uint8((value shr 8) and 0xFF)
  result.add uint8(value and 0xFF)


proc encodeLabelBytes(label: string): seq[uint8] =
  result = newSeq[uint8]()
  result.appendU32Be(uint32(label.len))
  for c in label:
    result.add uint8(ord(c))


proc privateKvContextLabel(owner: Principal): string =
  "private-kv-v1|owner=" & owner.text


proc privateKvInputLabel(owner: Principal, keyVersion: uint): string =
  "kv:" & owner.text & ":value-key:v" & $keyVersion


proc transportPublicKeyBytes(value: string): seq[uint8] =
  let cleaned = value.strip().replace(" ", "").replace("\n", "").replace("\t", "")
  if cleaned.len >= 2 and cleaned[0] == '0' and (cleaned[1] == 'x' or cleaned[1] == 'X'):
    return cleaned.hexToBytes()

  var looksHex = cleaned.len > 0 and cleaned.len mod 2 == 0
  if looksHex:
    for c in cleaned:
      if not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')):
        looksHex = false
        break

  if looksHex:
    return cleaned.hexToBytes()

  result = toBytes(value)


proc makeKeyId(): VetKdKeyId =
  VetKdKeyId(
    curve: VetKdCurve.bls12_381_g2,
    name: VetKdKeyName
  )


proc getPrivateKvEnvelope(
  caller: Principal,
  transportPublicKey: seq[uint8],
  keyVersion: uint
): Future[PrivateKvEnvelope] {.async.} =
  let contextLabel = privateKvContextLabel(caller)
  let inputLabel = privateKvInputLabel(caller, keyVersion)
  let contextBytes = encodeLabelBytes(contextLabel)
  let inputBytes = encodeLabelBytes(inputLabel)
  icEcho "[vetkey-debug] getPrivateKvEnvelope caller=" & caller.text &
    " keyVersion=" & $keyVersion & " vetKdKeyName=" & VetKdKeyName &
    " contextLabel=" & contextLabel & " inputLabel=" & inputLabel &
    " transportPkLen=" & $transportPublicKey.len &
    " contextBytesLen=" & $contextBytes.len & " inputBytesLen=" & $inputBytes.len
  icEcho "[vetkey-debug] getPrivateKvEnvelope calling vetkd_public_key"
  let publicKeyResult = await ManagementCanister.vetKdPublicKey(VetKdPublicKeyArgs(
    canister_id: none(Principal),
    context: contextBytes,
    key_id: makeKeyId()
  ))
  icEcho "[vetkey-debug] getPrivateKvEnvelope vetkd_public_key ok publicKeyLen=" &
    $publicKeyResult.public_key.len
  icEcho "[vetkey-debug] getPrivateKvEnvelope calling vetkd_derive_key"
  let deriveResult = await ManagementCanister.vetKdDeriveKey(VetKdDeriveKeyArgs(
    input: inputBytes,
    context: contextBytes,
    transport_public_key: transportPublicKey,
    key_id: makeKeyId()
  ))
  icEcho "[vetkey-debug] getPrivateKvEnvelope vetkd_derive_key ok encryptedKeyLen=" &
    $deriveResult.encrypted_key.len
  result = PrivateKvEnvelope(
    owner: caller,
    key_version: keyVersion,
    context_label: contextLabel,
    input_label: inputLabel,
    public_key_hex: publicKeyResult.public_key.toHexString(),
    encrypted_key_hex: deriveResult.encrypted_key.toHexString()
  )


proc derivePrivateKvEnvelope*() {.async.} =
  let request = Request.new()
  let transportPublicKeyText = request.getStr(0)
  let keyVersion = uint(request.getNat64(1))
  let caller = Msg.caller()

  let tpPreview =
    if transportPublicKeyText.len <= 32:
      transportPublicKeyText
    else:
      transportPublicKeyText[0..<32] & "..."
  icEcho "[vetkey-debug] derivePrivateKvEnvelope begin caller=" & caller.text &
    " keyVersion=" & $keyVersion & " transportPkTextLen=" & $transportPublicKeyText.len &
    " transportPkTextPrefix=" & tpPreview
  try:
    let transportPublicKey = transportPublicKeyBytes(transportPublicKeyText)
    icEcho "[vetkey-debug] derivePrivateKvEnvelopeImpl transportPkBytesLen=" &
      $transportPublicKey.len
    let envelope = await getPrivateKvEnvelope(caller, transportPublicKey, keyVersion)
    icEcho "[vetkey-debug] derivePrivateKvEnvelopeImpl ok context_label=" &
      envelope.context_label & " encrypted_key_hex_len=" &
      $envelope.encrypted_key_hex.len
    reply(envelope)
  except Exception as e:
    icEcho "[vetkey-debug] derivePrivateKvEnvelopeImpl ERROR: " & e.msg
    reject("Failed to derive private kv envelope: " & e.msg)
