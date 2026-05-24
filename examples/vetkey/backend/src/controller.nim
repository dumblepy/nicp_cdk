import std/asyncdispatch
import std/options
import std/strutils
import std/tables
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
  PrivateKvStoreSummary = object
    note_id: string
    owner: Principal
    key_version: uint
    ciphertext_len: uint
    nonce_len: uint
    aad_len: uint

  PrivateKvEntry = object
    owner: Principal
    key_version: uint
    ciphertext: seq[uint8]

  PrivateKvSnapshot = object
    owner: Principal
    key_version: uint
    ciphertext_hex: string

  PrivateKvEnvelope = object
    owner: Principal
    key_version: uint
    context_label: string
    input_label: string
    public_key_hex: string
    encrypted_key_hex: string


var
  privateKvNotes = initTable[string, PrivateKvEntry]()


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
  owner: Principal,
  transportPublicKey: seq[uint8],
  keyVersion: uint
): Future[PrivateKvEnvelope] {.async.} =
  let contextLabel = privateKvContextLabel(owner)
  let inputLabel = privateKvInputLabel(owner, keyVersion)
  let contextBytes = encodeLabelBytes(contextLabel)
  let inputBytes = encodeLabelBytes(inputLabel)
  icEcho "[vetkey-debug] getPrivateKvEnvelope owner=" & owner.text &
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
    owner: owner,
    key_version: keyVersion,
    context_label: contextLabel,
    input_label: inputLabel,
    public_key_hex: publicKeyResult.public_key.toHexString(),
    encrypted_key_hex: deriveResult.encrypted_key.toHexString()
  )
proc storePrivateKvImpl(ciphertext: seq[uint8], keyVersion: uint) {.used.} =
  try:
    let owner = Msg.caller()
    icEcho "[vetkey-debug] storePrivateKv begin caller=" & owner.text &
      " ciphertextLen=" & $ciphertext.len & " keyVersion=" & $keyVersion
    let note = PrivateKvEntry(
      owner: owner,
      key_version: keyVersion,
      ciphertext: ciphertext
    )
    privateKvNotes[owner.text] = note
    icEcho "[vetkey-debug] storePrivateKv done noteKey=" & owner.text
    reply(PrivateKvStoreSummary(
      note_id: owner.text,
      owner: owner,
      key_version: keyVersion,
      ciphertext_len: uint(ciphertext.len),
      nonce_len: 0'u,
      aad_len: 0'u
    ))
  except Exception as e:
    icEcho "[vetkey-debug] storePrivateKv ERROR: " & e.msg
    reject("Failed to store private kv: " & e.msg)


proc fetchPrivateKvImpl() {.used.} =
  try:
    let owner = Msg.caller()
    icEcho "[vetkey-debug] fetchPrivateKv begin caller=" & owner.text
    let key = owner.text
    if not privateKvNotes.hasKey(key):
      raise newException(ValueError, "Private KV not found: owner=" & owner.text)
    let note = privateKvNotes[key]
    icEcho "[vetkey-debug] fetchPrivateKv note key_version=" & $note.key_version &
      " ciphertextLen=" & $note.ciphertext.len
    reply(PrivateKvSnapshot(
      owner: note.owner,
      key_version: note.key_version,
      ciphertext_hex: note.ciphertext.toHexString()
    ))
  except Exception as e:
    icEcho "[vetkey-debug] fetchPrivateKv ERROR: " & e.msg
    reject("Failed to fetch private kv: " & e.msg)


proc derivePrivateKvKeyImpl(transportPublicKeyText: string, keyVersion: uint) {.async, used.} =
  let tpPreview =
    if transportPublicKeyText.len <= 32:
      transportPublicKeyText
    else:
      transportPublicKeyText[0..<32] & "..."
  icEcho "[vetkey-debug] derivePrivateKvKeyImpl begin caller=" & Msg.caller().text &
    " keyVersion=" & $keyVersion & " transportPkTextLen=" & $transportPublicKeyText.len &
    " transportPkTextPrefix=" & tpPreview
  try:
    let owner = Msg.caller()
    let transportPublicKey = transportPublicKeyBytes(transportPublicKeyText)
    icEcho "[vetkey-debug] derivePrivateKvKeyImpl transportPkBytesLen=" &
      $transportPublicKey.len
    let envelope = await getPrivateKvEnvelope(owner, transportPublicKey, keyVersion)
    icEcho "[vetkey-debug] derivePrivateKvKeyImpl ok context_label=" &
      envelope.context_label & " encrypted_key_hex_len=" &
      $envelope.encrypted_key_hex.len
    reply(envelope)
  except Exception as e:
    icEcho "[vetkey-debug] derivePrivateKvKeyImpl ERROR: " & e.msg
    reject("Failed to derive private kv key: " & e.msg)
