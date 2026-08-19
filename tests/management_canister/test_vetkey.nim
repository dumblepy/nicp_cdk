discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/management_canister/test_vetkey.nim
#
# vetKD 周りの検証。
# - vetKD Candid tests: CDK の Candid エンコード／デコードが型どおりか（icp 不要）。
# - vetKD integration tests: `icp` が PATH にあるときのみ。ローカル ICP 上の examples/vetkey
#   キャニスターを CLI 経由で呼び、caller と key version に応じた Private KV envelope を確認する。
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


when isMainModule:
  if findExe(ICP_PATH).len == 0:
    echo "Skipping test_vetkey because icp is unavailable in this environment."
    quit(0)


# 統合テスト用: icp CLI のラッパと `icp canister call` 向け Candid 引数の組み立て。
var
  alicePrincipal = ""
  bobPrincipal = ""
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


proc tupleArgs(args: seq[string]): string =
  "(" & args.join(", ") & ")"


proc nat64Literal(value: uint64): string =
  $value & ":nat64"


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
  # 現在の examples/vetkey は、キャニスタに暗号文を保存しない Private KV の
  # envelope API だけを公開している。identity ごとの context/input 分離と、
  # client 側の暗号化・復号を検証する。
  suite "vetKD integration tests":
    test "Prepare identities and deploy vetkey canister":
      ensureIdentity(VETKEY_DIR, ALICE_IDENTITY)
      ensureIdentity(VETKEY_DIR, BOB_IDENTITY)
      alicePrincipal = identityPrincipal(VETKEY_DIR, ALICE_IDENTITY)
      bobPrincipal = identityPrincipal(VETKEY_DIR, BOB_IDENTITY)
      deploy(VETKEY_DIR, CANISTER_NAME)
      check backendCanisterId.len > 0
      sleep(2000)

    test "Private KV envelope separates callers and key versions":
      let (_, transportPublicHex) = generateVetkeyTransportKeyPair()
      let aliceV1 = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateKvEnvelope",
        tupleArgs(@[quotedText(transportPublicHex), nat64Literal(1)]),
        ALICE_IDENTITY
      )
      let bobV1 = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateKvEnvelope",
        tupleArgs(@[quotedText(transportPublicHex), nat64Literal(1)]),
        BOB_IDENTITY
      )
      let aliceV2 = callCanisterSuccess(
        VETKEY_DIR,
        CANISTER_NAME,
        "derivePrivateKvEnvelope",
        tupleArgs(@[quotedText(transportPublicHex), nat64Literal(2)]),
        ALICE_IDENTITY
      )

      check extractQuotedField(aliceV1, "context_label") ==
        "private-kv-v1|owner=" & alicePrincipal
      check extractQuotedField(bobV1, "context_label") ==
        "private-kv-v1|owner=" & bobPrincipal
      check extractQuotedField(aliceV1, "input_label") ==
        privateKvInputLabel(alicePrincipal, 1)
      check extractQuotedField(aliceV2, "input_label") ==
        privateKvInputLabel(alicePrincipal, 2)
      check aliceV1 != bobV1
      check aliceV1 != aliceV2
      check aliceV1.contains("public_key_hex")
      check aliceV1.contains("encrypted_key_hex")

    test "Private KV roundtrip encrypts and decrypts by principal":
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
      let privateKvInput = privateKvInputLabel(alicePrincipal, 1)
      let privateKvContext = "private-kv-v1|owner=" & alicePrincipal
      let contextLabel = extractQuotedField(deriveOutput, "context_label")
      check contextLabel == privateKvContext
      let encryptedKeyHex = extractQuotedField(deriveOutput, "encrypted_key_hex")
      check extractQuotedField(deriveOutput, "input_label") == privateKvInput

      let ciphertextBytes = vetkeyEncryptMessage(
        transportSecretHex, encryptedKeyHex, plaintextBytes, domainSep
      )
      let decryptedBytes = vetkeyDecryptMessage(
        transportSecretHex,
        encryptedKeyHex,
        ciphertextBytes,
        domainSep,
      )
      check bytesToHex(decryptedBytes).toLowerAscii == plaintextHex.toLowerAscii
