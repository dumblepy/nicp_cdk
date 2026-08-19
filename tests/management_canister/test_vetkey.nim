discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/management_canister/test_vetkey.nim
#
# vetKD 周りの検証。
# - vetKD Candid tests: CDK の Candid エンコード／デコードが型どおりか（icp 不要）。
# - vetKD integration tests: `icp` が PATH にあるときのみ。ローカル ICP 上の examples/vetkey
#   キャニスターを CLI 経由で呼び、プライベート／共有ノートと ACL・エラー応答を確認する。
#   Private KV 往復の client 側暗号は `vetkey_roundtrip_crypto.nim`（rustcrypto BLS / HKDF / AES-GCM）で行う。

import std/unittest
import std/osproc
import std/strutils
import std/os
import std/options
import ../icp_network
import ./vetkey_types
import ../../src/nicp_cdk/ic_types/candid_types
import ../../src/nicp_cdk/ic_types/ic_principal
import ../../src/nicp_cdk/ic_types/ic_record
import ../../src/nicp_cdk/ic_types/candid_message/candid_encode
import ../../src/nicp_cdk/ic_types/candid_message/candid_decode
import ./vetkey_roundtrip_crypto

const
  ICP_PATH = "icp"
  VETKEY_DIR = "/application/examples/vetkey"
  CANISTER_NAME = "backend"
  ALICE_IDENTITY = "vetkey-alice"
  BOB_IDENTITY = "vetkey-bob"
  CAROL_IDENTITY = "vetkey-carol"
  GOOD_TRANSPORT_PUBLIC_KEY_HEX = "a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d"


when isMainModule:
  if findExe(ICP_PATH).len == 0:
    echo "Skipping test_vetkey because icp is unavailable in this environment."
    quit(0)


# 統合テスト用: icp CLI のラッパと `icp canister call` 向け Candid 引数の組み立て。
var
  alicePrincipal = ""
  bobPrincipal = ""
  carolPrincipal = ""
  backendCanisterId = ""


proc runIcpCommand(projectDir, command: string): tuple[output: string, exitCode: int] =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    result = execCmdEx(command)
  finally:
    setCurrentDir(originalDir)


proc identityList(projectDir: string): string =
  let (output, code) = runIcpCommand(projectDir, ICP_PATH & " identity list")
  check code == 0
  output


proc ensureIdentity(projectDir, identityName: string) =
  let listed = identityList(projectDir)
  for line in listed.splitLines:
    if line.strip() == identityName:
      return

  let (output, code) = runIcpCommand(projectDir, ICP_PATH & " identity new " & identityName & " --storage plaintext")
  if code == 0:
    return
  let lower = output.toLowerAscii()
  if lower.contains("already exists") or lower.contains("exists"):
    return
  check code == 0
  echo output


proc identityPrincipal(projectDir, identityName: string): string =
  let (output, code) = runIcpCommand(
    projectDir,
    ICP_PATH & " identity principal --identity " & identityName
  )
  check code == 0
  output.strip()


proc quotedText(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""


proc principalLiteral(value: string): string =
  "principal " & quotedText(value)


proc tupleArgs(args: seq[string]): string =
  "(" & args.join(", ") & ")"


proc nat64Literal(value: uint64): string =
  $value & ":nat64"


proc privateNoteArgs(noteId: string, keyVersion: uint64): string =
  tupleArgs(@[
    quotedText(noteId),
    quotedText("ciphertext:" & noteId),
    quotedText("nonce:" & noteId),
    quotedText("aad:" & noteId),
    nat64Literal(keyVersion)
  ])


proc sharedNoteArgs(noteId: string, keyVersion: uint64): string =
  tupleArgs(@[
    quotedText(noteId),
    quotedText("shared-ciphertext:" & noteId),
    quotedText("shared-nonce:" & noteId),
    quotedText("shared-aad:" & noteId),
    nat64Literal(keyVersion)
  ])


proc privateOwnerArgs(ownerPrincipal, noteId: string, transportPublicKey: string): string =
  tupleArgs(@[
    principalLiteral(ownerPrincipal),
    quotedText(noteId),
    quotedText(transportPublicKey)
  ])


proc sharedNoteKeyArgs(noteId, transportPublicKey: string): string =
  tupleArgs(@[
    quotedText(noteId),
    quotedText(transportPublicKey)
  ])


proc callCanisterFunction(
  projectDir: string,
  canisterName: string,
  functionName: string,
  args: string = "",
  outputCandid: bool = true,
  identityName: string = ""
): tuple[output: string, exitCode: int] =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let outputFlag = if outputCandid: " --output candid" else: ""
    let identityFlag = if identityName.len > 0: " --identity " & identityName else: ""
    let command = if args.len == 0:
      ICP_PATH & " canister call" & identityFlag & outputFlag & " " & canisterName & " " & functionName & " '()'"
    else:
      ICP_PATH & " canister call" & identityFlag & outputFlag & " " & canisterName & " " & functionName & " '" & args & "'"
    echo command
    result = execCmdEx(command)
  finally:
    setCurrentDir(originalDir)


proc callCanisterSuccess(
  projectDir: string,
  canisterName: string,
  functionName: string,
  args: string = "",
  identityName: string = ""
): string =
  let (output, code) = callCanisterFunction(projectDir, canisterName, functionName, args, true, identityName)
  check code == 0
  output.strip()


proc callCanisterFailure(
  projectDir: string,
  canisterName: string,
  functionName: string,
  args: string = "",
  identityName: string = ""
): string =
  let (output, code) = callCanisterFunction(projectDir, canisterName, functionName, args, true, identityName)
  let lower = output.toLowerAscii()
  check code != 0 or lower.contains("reject") or lower.contains("error") or lower.contains("failed")
  output.strip()


proc deploy(projectDir: string, canisterName: string) =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let deployResult = execCmdEx(ICP_PATH & " deploy -y")
    check deployResult.exitCode == 0
    check deployResult.output.contains("Deployed") or deployResult.output.contains("Creating") or
          deployResult.output.contains("Installing") or deployResult.output.contains(canisterName)
    for line in deployResult.output.splitLines:
      let prefix = "Created canister " & canisterName & " with ID "
      if line.contains(prefix):
        backendCanisterId = line.substr(line.find(prefix) + prefix.len)
        backendCanisterId = backendCanisterId.strip()
        break
  finally:
    setCurrentDir(originalDir)


proc bytesToHex(value: seq[uint8]): string =
  result = newStringOfCap(value.len * 2)
  for b in value:
    result.add(b.toHex(2))


proc textToBytes(value: string): seq[uint8] =
  result = newSeq[uint8](value.len)
  for i, c in value:
    result[i] = uint8(ord(c))


proc extractQuotedField(output, fieldName: string): string =
  let needle = fieldName & " = \""
  let start = output.find(needle)
  check start >= 0
  let valueStart = start + needle.len
  let valueEnd = output.find('"', valueStart)
  check valueEnd >= 0
  output[valueStart ..< valueEnd]


proc privateKvInputLabel(ownerPrincipal: string, keyVersion: uint64): string =
  "kv:" & ownerPrincipal & ":value-key:v" & $keyVersion


# 管理キャニスタ向け vetKD 引数の Candid 表現が、往復後も期待するフィールド構造になること。
suite "vetKD Candid tests":
  test "VetKdKeyId encodes to a record with the expected curve variant":
    # name がテキスト、curve が期待のバリアント（例: bls12_381_g2）としてレコードに載ること。
    let keyId = VetKdKeyId(curve: VetKdCurve.bls12_381_g2, name: "test_key_1")
    let encoded = encodeCandidMessage(@[recordToCandidValue(%keyId)])
    let decoded = decodeCandidMessage(encoded)
    check decoded.values.len == 1
    let record = candidValueToCandidRecord(decoded.values[0])
    check record["name"].getStr() == "test_key_1"
    check record["curve"].getVariant(VetKdCurve) == VetKdCurve.bls12_381_g2

  test "VetKdPublicKeyArgs encodes opt principal and blob fields":
    # canister_id が none のとき opt として欠け、context が blob、key_id がネストレコードになること。
    let args = VetKdPublicKeyArgs(
      canister_id: none(Principal),
      context: @[1'u8, 2'u8, 3'u8],
      key_id: VetKdKeyId(curve: VetKdCurve.bls12_381_g2, name: "test_key_1")
    )
    let encoded = encodeCandidMessage(@[recordToCandidValue(%args)])
    let decoded = decodeCandidMessage(encoded)
    check decoded.values.len == 1
    let record = candidValueToCandidRecord(decoded.values[0])
    check record["canister_id"].isNone()
    check record["context"].getBlob() == @[1'u8, 2'u8, 3'u8]
    check record["key_id"]["name"].getStr() == "test_key_1"

  test "VetKdDeriveKeyArgs encodes blobs":
    # input / context / transport_public_key がそれぞれ blob として往復すること。
    let args = VetKdDeriveKeyArgs(
      input: @[4'u8, 5'u8, 6'u8],
      context: @[7'u8, 8'u8],
      transport_public_key: @[9'u8, 10'u8],
      key_id: VetKdKeyId(curve: VetKdCurve.bls12_381_g2, name: "test_key_1")
    )
    let encoded = encodeCandidMessage(@[recordToCandidValue(%args)])
    let decoded = decodeCandidMessage(encoded)
    check decoded.values.len == 1
    let record = candidValueToCandidRecord(decoded.values[0])
    check record["input"].getBlob() == @[4'u8, 5'u8, 6'u8]
    check record["context"].getBlob() == @[7'u8, 8'u8]
    check record["transport_public_key"].getBlob() == @[9'u8, 10'u8]


withIcpNetwork(VETKEY_DIR):
  # examples/vetkey をデプロイし、identity 付きの canister call でサンプル API の振る舞いを検証する。
  suite "vetKD integration tests":
    test "Prepare identities and deploy vetkey canister":
      # Alice/Bob/Carol の identity と principal を用意し、backend キャニスタをデプロイする前提整備。
      ensureIdentity(VETKEY_DIR, ALICE_IDENTITY)
      ensureIdentity(VETKEY_DIR, BOB_IDENTITY)
      ensureIdentity(VETKEY_DIR, CAROL_IDENTITY)
      alicePrincipal = identityPrincipal(VETKEY_DIR, ALICE_IDENTITY)
      bobPrincipal = identityPrincipal(VETKEY_DIR, BOB_IDENTITY)
      carolPrincipal = identityPrincipal(VETKEY_DIR, CAROL_IDENTITY)
      deploy(VETKEY_DIR, CANISTER_NAME)
      check backendCanisterId.len > 0
      sleep(2000)

    test "Private notes keep caller-specific context and resource-specific input":
      # 別ユーザー・別ノートで describe が principal 付きメタを返し、derive の応答に
      # ノート別ラベルと public_key / encrypted_key が含まれること。Alice と Bob のエンベロープは一致しないこと。
      let aliceNote = "alice-note"
      let bobNote = "bob-note"

      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createPrivateNote",
        privateNoteArgs(aliceNote, 1),
        ALICE_IDENTITY
      )
      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createPrivateNote",
        privateNoteArgs(bobNote, 1),
        BOB_IDENTITY
      )

      let aliceSummary = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describePrivateNote",
        tupleArgs(@[principalLiteral(alicePrincipal), quotedText(aliceNote)]),
        ALICE_IDENTITY
      )
      let bobSummary = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describePrivateNote",
        tupleArgs(@[principalLiteral(bobPrincipal), quotedText(bobNote)]),
        BOB_IDENTITY
      )
      check aliceSummary.contains("ciphertext_len")
      check aliceSummary.contains("note_id")
      check aliceSummary.contains(alicePrincipal)
      check bobSummary.contains("ciphertext_len")
      check bobSummary.contains("note_id")
      check bobSummary.contains(bobPrincipal)

      let aliceEnvelope = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, aliceNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      let bobEnvelope = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(bobPrincipal, bobNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        BOB_IDENTITY
      )
      check aliceEnvelope.contains("encrypted-notes-v1|owner=")
      check bobEnvelope.contains("encrypted-notes-v1|owner=")
      check aliceEnvelope.contains("note:alice-note:key:v1")
      check bobEnvelope.contains("note:bob-note:key:v1")
      check aliceEnvelope != bobEnvelope
      check aliceEnvelope.contains("public_key")
      check aliceEnvelope.contains("encrypted_key")

    test "Private note access control rejects a different caller":
      # 所有者以外（Bob）が Alice のプライベートノートで derivePrivateNoteKey すると拒否されること。
      let unauthorized = callCanisterFailure(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, "alice-note", GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        BOB_IDENTITY
      )
      check unauthorized.contains("Unauthorized private note access")
      check unauthorized.contains(alicePrincipal)
      check unauthorized.contains(bobPrincipal)

    test "Resource isolation changes the private note input label":
      # 同一オーナーでも note_id が異なれば鍵導出ラベルとエンベロープが別物になること（リソース分離）。
      let firstNote = "alice-resource-1"
      let secondNote = "alice-resource-2"

      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createPrivateNote",
        privateNoteArgs(firstNote, 1),
        ALICE_IDENTITY
      )
      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createPrivateNote",
        privateNoteArgs(secondNote, 1),
        ALICE_IDENTITY
      )

      let firstEnvelope = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, firstNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      let secondEnvelope = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, secondNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      check firstEnvelope.contains("note:alice-resource-1:key:v1")
      check secondEnvelope.contains("note:alice-resource-2:key:v1")
      check firstEnvelope != secondEnvelope

    test "Key rotation changes the input label and keeps the note metadata versioned":
      # rotatePrivateNoteKey 後は derive のラベルが v2 に変わり、describe に key_version が反映されること。
      let rotatedNote = "alice-rotation"

      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createPrivateNote",
        privateNoteArgs(rotatedNote, 1),
        ALICE_IDENTITY
      )
      let beforeRotation = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, rotatedNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "rotatePrivateNoteKey",
        tupleArgs(@[principalLiteral(alicePrincipal), quotedText(rotatedNote), nat64Literal(2)]),
        ALICE_IDENTITY
      )
      let afterRotation = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describePrivateNote",
        tupleArgs(@[principalLiteral(alicePrincipal), quotedText(rotatedNote)]),
        ALICE_IDENTITY
      )
      let rotatedEnvelope = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateNoteKey",
        privateOwnerArgs(alicePrincipal, rotatedNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      check beforeRotation.contains("note:alice-rotation:key:v1")
      check rotatedEnvelope.contains("note:alice-rotation:key:v2")
      check rotatedEnvelope != beforeRotation
      check afterRotation.contains("key_version")
      check afterRotation.contains("2")

    test "Shared notes allow authorized callers and reject revoked callers":
      # 付与された二者の deriveSharedNoteKey が同一応答。revoke 後は ACL と derive が Bob を拒否すること。
      let sharedNote = "shared-team-note"

      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "createSharedNote",
        sharedNoteArgs(sharedNote, 1),
        ALICE_IDENTITY
      )
      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "grantSharedNoteAccess",
        tupleArgs(@[quotedText(sharedNote), principalLiteral(bobPrincipal)]),
        ALICE_IDENTITY
      )

      let aliceShared = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "deriveSharedNoteKey",
        sharedNoteKeyArgs(sharedNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      let bobShared = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "deriveSharedNoteKey",
        sharedNoteKeyArgs(sharedNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        BOB_IDENTITY
      )
      check aliceShared.contains("shared-note-v1|note=shared-team-note")
      check aliceShared.contains("content-key:v1")
      check aliceShared == bobShared

      let sharedSummary = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describeSharedNote",
        tupleArgs(@[quotedText(sharedNote)]),
        ALICE_IDENTITY
      )
      check sharedSummary.contains(alicePrincipal)
      check sharedSummary.contains(bobPrincipal)
      check sharedSummary.contains("acl")

      discard callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "revokeSharedNoteAccess",
        tupleArgs(@[quotedText(sharedNote), principalLiteral(bobPrincipal)]),
        ALICE_IDENTITY
      )
      let revokedSummary = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describeSharedNote",
        tupleArgs(@[quotedText(sharedNote)]),
        ALICE_IDENTITY
      )
      check revokedSummary.contains(alicePrincipal)
      check not revokedSummary.contains(bobPrincipal)

      let revokedFailure = callCanisterFailure(
        VETKEY_DIR,
        CANISTER_NAME,
        "deriveSharedNoteKey",
        sharedNoteKeyArgs(sharedNote, GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        BOB_IDENTITY
      )
      check revokedFailure.contains("Unauthorized shared note access")
      check revokedFailure.contains(bobPrincipal)

    test "Missing resources and invalid transport keys fail cleanly":
      # 存在しない共有ノートと不正な transport 公開鍵で、期待するエラーメッセージ／失敗になること。
      let missingResource = callCanisterFailure(
        VETKEY_DIR,
        CANISTER_NAME,
        "deriveSharedNoteKey",
        sharedNoteKeyArgs("missing-shared-note", GOOD_TRANSPORT_PUBLIC_KEY_HEX),
        ALICE_IDENTITY
      )
      check missingResource.contains("Shared note not found")

      let invalidTransportKey = callCanisterFailure(
        VETKEY_DIR,
        CANISTER_NAME,
        "deriveSharedNoteKey",
        sharedNoteKeyArgs("shared-team-note", "invalid-transport-key"),
        ALICE_IDENTITY
      )
      check invalidTransportKey.contains("Failed to derive shared note key")
      check invalidTransportKey.contains("reject") or invalidTransportKey.contains("error")

    test "Metadata-only storage keeps note summaries free of secret key material":
      # describePrivateNote は長さ・key_version などメタのみで、鍵素材相当の文字列を返さないこと。
      let metadataSummary = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "describePrivateNote",
        tupleArgs(@[principalLiteral(alicePrincipal), quotedText("alice-resource-1")]),
        ALICE_IDENTITY
      )
      check metadataSummary.contains("ciphertext_len")
      check metadataSummary.contains("nonce_len")
      check metadataSummary.contains("aad_len")
      check metadataSummary.contains("key_version")
      check not metadataSummary.toLowerAscii.contains("encrypted_key")
      check not metadataSummary.toLowerAscii.contains("public_key")
      check not metadataSummary.toLowerAscii.contains("symmetric")

    test "Private KV roundtrip encrypts and decrypts by principal":
      # principal を key にした vetKey を導出し、ciphertext は canister に保存せず
      # client 側だけで暗号化・復号して元の平文と一致することを確認する。
      let plaintext = "user secret payload for private kv"
      let plaintextBytes = textToBytes(plaintext)
      let plaintextHex = bytesToHex(plaintextBytes)
      let domainSep = "private-kv-v1"

      let (transportSecretHex, transportPublicHex) = generateVetkeyTransportKeyPair()

      let deriveOutput = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateKvEnvelope",
        tupleArgs(@[quotedText(transportPublicHex), nat64Literal(1)]),
        ALICE_IDENTITY
      )
      check deriveOutput.contains("private-kv-v1|owner=" & alicePrincipal)

      let privateKvInput = privateKvInputLabel(alicePrincipal, 1)
      let privateKvContext = "private-kv-v1|owner=" & alicePrincipal
      let contextLabel = extractQuotedField(deriveOutput, "context_label")
      check contextLabel == privateKvContext
      let encryptedKeyHex = extractQuotedField(deriveOutput, "encrypted_key_hex")
      check deriveOutput.contains(privateKvInput)

      let ciphertextBytes = vetkeyEncryptMessage(
        transportSecretHex, encryptedKeyHex, plaintextBytes, domainSep
      )

      let decryptedBytes = vetkeyDecryptMessage(
        transportSecretHex,
        encryptedKeyHex,
        ciphertextBytes,
        domainSep,
      )
      let decryptedHex = bytesToHex(decryptedBytes)
      check decryptedHex.toLowerAscii == plaintextHex.toLowerAscii
