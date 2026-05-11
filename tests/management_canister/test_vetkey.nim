discard """
  cmd: "nim c --skipUserCfg $file"
"""

# nim c -r --skipUserCfg tests/management_canister/test_vetkey.nim

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

const
  ICP_PATH = "icp"
  VETKEY_DIR = "/application/examples/vetkey"
  CANISTER_NAME = "backend"


proc callCanisterFunction(
  projectDir: string,
  canisterName: string,
  functionName: string,
  args: string = "",
  outputCandid: bool = true
): string =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let outputFlag = if outputCandid: " --output candid" else: ""
    let command = if args == "":
      ICP_PATH & " canister call" & outputFlag & " " & canisterName & " " & functionName & " '()'"
    else:
      ICP_PATH & " canister call" & outputFlag & " " & canisterName & " " & functionName & " '(" & args & ")'"
    echo command
    execProcess(command).strip()
  finally:
    setCurrentDir(originalDir)


proc deploy(projectDir: string, canisterName: string) =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let deployResult = execProcess(ICP_PATH & " deploy -y")
    check deployResult.contains("Deployed") or deployResult.contains("Creating") or
          deployResult.contains("Installing") or deployResult.contains(canisterName)
  finally:
    setCurrentDir(originalDir)


suite "vetKD Candid tests":
  test "VetKdKeyId encodes to a record with the expected curve variant":
    let keyId = VetKdKeyId(curve: VetKdCurve.bls12_381_g2, name: "test_key_1")
    let encoded = encodeCandidMessage(@[recordToCandidValue(%keyId)])
    let decoded = decodeCandidMessage(encoded)
    check decoded.values.len == 1
    let record = candidValueToCandidRecord(decoded.values[0])
    check record["name"].getStr() == "test_key_1"
    check record["curve"].getVariant(VetKdCurve) == VetKdCurve.bls12_381_g2

  test "VetKdPublicKeyArgs encodes opt principal and blob fields":
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


let canRunIntegration = findExe("icp").len > 0

if canRunIntegration:
  withIcpNetwork(VETKEY_DIR):
    suite "vetKD integration tests":
      test "Deploy vetkey canister":
        deploy(VETKEY_DIR, CANISTER_NAME)
        sleep(2000)

      test "getPublicKey returns a blob":
        let result = callCanisterFunction(VETKEY_DIR, CANISTER_NAME, "getPublicKey")
        echo result
        check result.len > 0
        check result.contains("blob") or result.contains("\"")

      test "deriveKey returns an encrypted blob":
        let result = callCanisterFunction(VETKEY_DIR, CANISTER_NAME, "deriveKey")
        echo result
        check result.len > 0
        check result.contains("blob") or result.contains("\"")
else:
  echo "Skipping vetkey integration tests because icp is unavailable."
