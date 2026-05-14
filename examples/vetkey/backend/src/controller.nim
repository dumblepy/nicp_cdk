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
  VetKdContext = "vetkey_example_v1"
  ## `icp` の managed ローカルレプリカは vetKD しきい値として **`key_1`** のみ公開する（`test_key_1` は無い）。
  ## dfx の一部環境では `test_key_1` がある場合があるため、レプリカのエラーに従って切り替えること。
  VetKdKeyName = "key_1"
  VetKdSampleTransportPublicKeyHex = "a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d"


type
  PrivateNote = object
    note_id: string
    owner: Principal
    ciphertext: seq[uint8]
    nonce: seq[uint8]
    aad: seq[uint8]
    key_version: uint

  SharedNote = object
    note_id: string
    owner: Principal
    ciphertext: seq[uint8]
    nonce: seq[uint8]
    aad: seq[uint8]
    key_version: uint
    acl: seq[Principal]

  NoteSummary = object
    note_id: string
    owner: Principal
    key_version: uint
    ciphertext_len: uint
    nonce_len: uint
    aad_len: uint

  SharedNoteSummary = object
    note_id: string
    owner: Principal
    key_version: uint
    ciphertext_len: uint
    nonce_len: uint
    aad_len: uint
    acl: seq[Principal]

  NoteKeyEnvelope = object
    note_id: string
    owner: Principal
    key_version: uint
    context_label: string
    input_label: string
    public_key: seq[uint8]
    encrypted_key: seq[uint8]

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
  privateNotes = initTable[string, PrivateNote]()
  sharedNotes = initTable[string, SharedNote]()


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


proc noteKey(owner: Principal, noteId: string): string =
  owner.text & "|" & noteId


proc sharedNoteKey(noteId: string): string =
  noteId


proc privateContextLabel(owner: Principal): string =
  "encrypted-notes-v1|owner=" & owner.text


proc privateInputLabel(noteId: string, keyVersion: uint): string =
  "note:" & noteId & ":key:v" & $keyVersion


proc privateKvContextLabel(owner: Principal): string =
  "private-kv-v1|owner=" & owner.text


proc privateKvInputLabel(owner: Principal, keyVersion: uint): string =
  "kv:" & owner.text & ":value-key:v" & $keyVersion


proc sharedContextLabel(noteId: string): string =
  "shared-note-v1|note=" & noteId


proc sharedInputLabel(keyVersion: uint): string =
  "content-key:v" & $keyVersion


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


proc summary(note: PrivateNote): NoteSummary =
  NoteSummary(
    note_id: note.note_id,
    owner: note.owner,
    key_version: note.key_version,
    ciphertext_len: uint(note.ciphertext.len),
    nonce_len: uint(note.nonce.len),
    aad_len: uint(note.aad.len)
  )


proc summary(note: SharedNote): SharedNoteSummary =
  SharedNoteSummary(
    note_id: note.note_id,
    owner: note.owner,
    key_version: note.key_version,
    ciphertext_len: uint(note.ciphertext.len),
    nonce_len: uint(note.nonce.len),
    aad_len: uint(note.aad.len),
    acl: note.acl
  )


proc containsPrincipal(values: seq[Principal], target: Principal): bool =
  for value in values:
    if value.text == target.text:
      return true
  false


proc addPrincipal(values: var seq[Principal], target: Principal) =
  if not values.containsPrincipal(target):
    values.add target


proc removePrincipal(values: var seq[Principal], target: Principal) =
  for i, value in values:
    if value.text == target.text:
      values.delete(i)
      return


proc getPrivateNote(owner: Principal, noteId: string): PrivateNote =
  let key = noteKey(owner, noteId)
  if not privateNotes.hasKey(key):
    raise newException(ValueError, "Private note not found: owner=" & owner.text & ", note_id=" & noteId)
  result = privateNotes[key]


proc getSharedNote(noteId: string): SharedNote =
  let key = sharedNoteKey(noteId)
  if not sharedNotes.hasKey(key):
    raise newException(ValueError, "Shared note not found: note_id=" & noteId)
  result = sharedNotes[key]


proc requirePrivateOwner(owner: Principal, noteId: string) =
  let caller = Msg.caller()
  if caller.text != owner.text:
    raise newException(ValueError,
      "Unauthorized private note access: caller=" & caller.text & ", owner=" & owner.text & ", note_id=" & noteId)


proc requireSharedAccess(note: SharedNote) =
  let caller = Msg.caller()
  if not note.acl.containsPrincipal(caller):
    raise newException(ValueError,
      "Unauthorized shared note access: caller=" & caller.text & ", note_id=" & note.note_id)


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


proc callerInput(): seq[uint8] =
  let caller = Msg.caller()
  result = newSeq[uint8](caller.bytes.len)
  for i, b in caller.bytes:
    result[i] = uint8(b)


proc makeDeriveArgs(transportPublicKey: seq[uint8]): VetKdDeriveKeyArgs =
  VetKdDeriveKeyArgs(
    input: callerInput(),
    context: VetKdContext.toBytes(),
    transport_public_key: transportPublicKey,
    key_id: makeKeyId()
  )


proc getPrivateNoteEnvelope(
  owner: Principal,
  noteId: string,
  transportPublicKey: seq[uint8]
): Future[NoteKeyEnvelope] {.async.} =
  requirePrivateOwner(owner, noteId)
  let note = getPrivateNote(owner, noteId)
  let contextLabel = privateContextLabel(owner)
  let inputLabel = privateInputLabel(note.note_id, note.key_version)
  let contextBytes = encodeLabelBytes(contextLabel)
  let inputBytes = encodeLabelBytes(inputLabel)
  let publicKeyResult = await ManagementCanister.vetKdPublicKey(VetKdPublicKeyArgs(
    canister_id: none(Principal),
    context: contextBytes,
    key_id: makeKeyId()
  ))
  let deriveResult = await ManagementCanister.vetKdDeriveKey(VetKdDeriveKeyArgs(
    input: inputBytes,
    context: contextBytes,
    transport_public_key: transportPublicKey,
    key_id: makeKeyId()
  ))
  result = NoteKeyEnvelope(
    note_id: note.note_id,
    owner: note.owner,
    key_version: note.key_version,
    context_label: contextLabel,
    input_label: inputLabel,
    public_key: publicKeyResult.public_key,
    encrypted_key: deriveResult.encrypted_key
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


proc getSharedNoteEnvelope(
  noteId: string,
  transportPublicKey: seq[uint8]
): Future[NoteKeyEnvelope] {.async.} =
  let note = getSharedNote(noteId)
  requireSharedAccess(note)
  let contextLabel = sharedContextLabel(note.note_id)
  let inputLabel = sharedInputLabel(note.key_version)
  let contextBytes = encodeLabelBytes(contextLabel)
  let inputBytes = encodeLabelBytes(inputLabel)
  let publicKeyResult = await ManagementCanister.vetKdPublicKey(VetKdPublicKeyArgs(
    canister_id: none(Principal),
    context: contextBytes,
    key_id: makeKeyId()
  ))
  let deriveResult = await ManagementCanister.vetKdDeriveKey(VetKdDeriveKeyArgs(
    input: inputBytes,
    context: contextBytes,
    transport_public_key: transportPublicKey,
    key_id: makeKeyId()
  ))
  result = NoteKeyEnvelope(
    note_id: note.note_id,
    owner: note.owner,
    key_version: note.key_version,
    context_label: contextLabel,
    input_label: inputLabel,
    public_key: publicKeyResult.public_key,
    encrypted_key: deriveResult.encrypted_key
  )


proc getPublicKeyImpl() {.async.} =
  try:
    let publicKeyResult = await ManagementCanister.vetKdPublicKey(getPublicKeyArgs())
    reply(publicKeyResult.public_key)
  except Exception as e:
    reject("Failed to get vetKD public key: " & e.msg)


proc deriveKeyImpl() {.async.} =
  try:
    let transportPublicKey = VetKdSampleTransportPublicKeyHex.hexToBytes()
    let deriveResult = await ManagementCanister.vetKdDeriveKey(makeDeriveArgs(transportPublicKey))
    reply(deriveResult.encrypted_key)
  except Exception as e:
    reject("Failed to derive vetKD key: " & e.msg)


proc deriveKeyWithTransportPublicKeyImpl() {.async.} =
  try:
    let request = Request.new()
    let transportPublicKey = request.getBlob(0)
    let deriveResult = await ManagementCanister.vetKdDeriveKey(makeDeriveArgs(transportPublicKey))
    reply(deriveResult.encrypted_key)
  except Exception as e:
    reject("Failed to derive vetKD key with transport public key: " & e.msg)


proc createPrivateNoteImpl(noteId: string, ciphertext: string, nonce: string, aad: string, keyVersion: uint) =
  try:
    let owner = Msg.caller()
    let note = PrivateNote(
      note_id: noteId,
      owner: owner,
      ciphertext: ciphertext.toBytes(),
      nonce: nonce.toBytes(),
      aad: aad.toBytes(),
      key_version: keyVersion
    )
    privateNotes[noteKey(owner, noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to create private note: " & e.msg)


proc storePrivateKvImpl(ciphertext: seq[uint8], keyVersion: uint) =
  try:
    let owner = Msg.caller()
    icEcho "[vetkey-debug] storePrivateKv begin caller=" & owner.text &
      " ciphertextLen=" & $ciphertext.len & " keyVersion=" & $keyVersion
    let note = PrivateNote(
      note_id: owner.text,
      owner: owner,
      ciphertext: ciphertext,
      nonce: @[],
      aad: @[],
      key_version: keyVersion
    )
    privateNotes[noteKey(owner, owner.text)] = note
    icEcho "[vetkey-debug] storePrivateKv done noteKey=" & noteKey(owner, owner.text)
    reply(note.summary())
  except Exception as e:
    icEcho "[vetkey-debug] storePrivateKv ERROR: " & e.msg
    reject("Failed to store private kv: " & e.msg)


proc describePrivateNoteImpl(owner: Principal, noteId: string) =
  try:
    requirePrivateOwner(owner, noteId)
    let note = getPrivateNote(owner, noteId)
    reply(note.summary())
  except Exception as e:
    reject("Failed to describe private note: " & e.msg)


proc fetchPrivateKvImpl() =
  try:
    let owner = Msg.caller()
    icEcho "[vetkey-debug] fetchPrivateKv begin caller=" & owner.text
    let note = getPrivateNote(owner, owner.text)
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


proc rotatePrivateNoteKeyImpl(owner: Principal, noteId: string, keyVersion: uint) =
  try:
    requirePrivateOwner(owner, noteId)
    var note = getPrivateNote(owner, noteId)
    note.key_version = keyVersion
    privateNotes[noteKey(owner, noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to rotate private note key: " & e.msg)


proc derivePrivateNoteKeyImpl(owner: Principal, noteId: string, transportPublicKeyText: string) {.async.} =
  try:
    let transportPublicKey = transportPublicKeyBytes(transportPublicKeyText)
    let envelope = await getPrivateNoteEnvelope(owner, noteId, transportPublicKey)
    reply(envelope)
  except Exception as e:
    reject("Failed to derive private note key: " & e.msg)


proc derivePrivateKvKeyImpl(transportPublicKeyText: string, keyVersion: uint) {.async.} =
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


proc createSharedNoteImpl(noteId: string, ciphertext: string, nonce: string, aad: string, keyVersion: uint) =
  try:
    let owner = Msg.caller()
    let note = SharedNote(
      note_id: noteId,
      owner: owner,
      ciphertext: ciphertext.toBytes(),
      nonce: nonce.toBytes(),
      aad: aad.toBytes(),
      key_version: keyVersion,
      acl: @[owner]
    )
    sharedNotes[sharedNoteKey(noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to create shared note: " & e.msg)


proc describeSharedNoteImpl(noteId: string) =
  try:
    let note = getSharedNote(noteId)
    requireSharedAccess(note)
    reply(note.summary())
  except Exception as e:
    reject("Failed to describe shared note: " & e.msg)


proc grantSharedNoteAccessImpl(noteId: string, principal: Principal) =
  try:
    var note = getSharedNote(noteId)
    if Msg.caller().text != note.owner.text:
      raise newException(ValueError,
        "Only the owner can grant shared note access: caller=" & Msg.caller().text & ", note_id=" & noteId)
    note.acl.addPrincipal(principal)
    sharedNotes[sharedNoteKey(noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to grant shared note access: " & e.msg)


proc revokeSharedNoteAccessImpl(noteId: string, principal: Principal) =
  try:
    var note = getSharedNote(noteId)
    if Msg.caller().text != note.owner.text:
      raise newException(ValueError,
        "Only the owner can revoke shared note access: caller=" & Msg.caller().text & ", note_id=" & noteId)
    if principal.text == note.owner.text:
      raise newException(ValueError, "The shared note owner cannot be revoked: note_id=" & noteId)
    note.acl.removePrincipal(principal)
    sharedNotes[sharedNoteKey(noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to revoke shared note access: " & e.msg)


proc rotateSharedNoteKeyImpl(noteId: string, keyVersion: uint) =
  try:
    var note = getSharedNote(noteId)
    if Msg.caller().text != note.owner.text:
      raise newException(ValueError,
        "Only the owner can rotate the shared note key: caller=" & Msg.caller().text & ", note_id=" & noteId)
    note.key_version = keyVersion
    sharedNotes[sharedNoteKey(noteId)] = note
    reply(note.summary())
  except Exception as e:
    reject("Failed to rotate shared note key: " & e.msg)


proc deriveSharedNoteKeyImpl(noteId: string, transportPublicKeyText: string) {.async.} =
  try:
    let transportPublicKey = transportPublicKeyBytes(transportPublicKeyText)
    let envelope = await getSharedNoteEnvelope(noteId, transportPublicKey)
    reply(envelope)
  except Exception as e:
    reject("Failed to derive shared note key: " & e.msg)
