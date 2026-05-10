discard """
  cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/test_encode_response.nim

import unittest
import std/os
import std/strutils
import std/osproc
import std/tables
import icp_network
import ../src/nicp_cdk/ic_types/candid_message/candid_decode
import ../src/nicp_cdk/ic_types/candid_types
import ../src/nicp_cdk/ic_types/type_transfer
import ../src/nicp_cdk/request
const ICP_PATH = "icp"
const MOTOKO_DIR = "/application/examples/type_test/motoko"
const NIM_DIR = "/application/examples/type_test/nim"

var motokoResults = initTable[string, string]()
var nimResults = initTable[string, string]()

const COMPARE_FUNCTIONS = [
  "responseNull",
  "responseEmpty",
  "boolFunc",
  "intFunc",
  "int8Func",
  "int16Func",
  "int32Func",
  "int64Func",
  "natFunc",
  "nat8Func",
  "nat16Func",
  "nat32Func",
  "nat64Func",
  "floatFunc",
  "textFunc",
  "blobFunc",
  "vecNatFunc",
  "vecTextFunc",
  "vecBoolFunc",
  "vecIntFunc",
  "vecVecNatFunc",
  "vecVecTextFunc",
  "vecVecBoolFunc",
  "vecVecIntFunc",
  "optTextSome",
  "optTextNone",
  "optIntSome",
  "optIntNone",
  "optNatSome",
  "optNatNone",
  "optFloatSome",
  "optFloatNone",
  "optBoolSome",
  "optBoolNone",
  "recordSimple",
  "recordNested",
  "principalFunc",
  "principalAnonymous",
  "principalCanister",
  "variantColorRed",
  "variantColorGreen",
  "variantColorBlue",
  "funcRefTextQuery",
]

proc hexToBytes(hexValue: string): seq[byte] =
  var cleaned = hexValue.strip().replace(" ", "").replace("\n", "").replace("\t", "")
  if cleaned.len >= 2 and cleaned[0] == '0' and (cleaned[1] == 'x' or cleaned[1] == 'X'):
    cleaned = cleaned[2..^1]
  if cleaned.len == 0:
    return @[]
  doAssert cleaned.len mod 2 == 0
  result = newSeq[byte](cleaned.len div 2)
  for i in 0 ..< result.len:
    let start = i * 2
    result[i] = byte(parseHexInt(cleaned[start ..< start + 2]))

proc extractHexPayload(output: string): string =
  for line in output.splitLines:
    let cleaned = line.strip().replace(" ", "")
    if cleaned.len > 0:
      var isHex = true
      for ch in cleaned:
        if not (ch in {'0'..'9', 'a'..'f', 'A'..'F'}):
          isHex = false
          break
      if isHex:
        result = cleaned
  if result.len == 0:
    result = output.strip().replace(" ", "")

proc runCommand(command: string) =
  let (output, code) = execCmdEx(command)
  check code == 0
  if code != 0:
    echo "command: ", command
    echo "output: ", output

proc callProjectCanisterFunction(projectDir, functionName: string, args: string = ""): string =
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let command = if args == "":
      ICP_PATH & " canister call backend " & functionName & " '()' --output hex"
    else:
      ICP_PATH & " canister call backend " & functionName & " '" & args & "'" & " --output hex"
    return extractHexPayload(execProcess(command))
  finally:
    setCurrentDir(originalDir)

proc callNimCanisterFunction(functionName: string, args: string = ""): string =
  if args == "" and functionName in nimResults:
    return nimResults[functionName]

  return callProjectCanisterFunction(NIM_DIR, functionName, args)


proc callMotokoCanisterFunction(functionName: string, args: string = ""): string =
  if args == "" and functionName in motokoResults:
    return motokoResults[functionName]

  return callProjectCanisterFunction(MOTOKO_DIR, functionName, args)


proc rowTest(fucName:string):bool =
  return motokoResults[fucName] == nimResults[fucName]


proc deploy() =
  echo "Deploying canisters..."
  let originalDir = getCurrentDir()
  
  try:
    # Motokoキャニスターのデプロイ
    ensureIcpNetworkStarted(MOTOKO_DIR)
    setCurrentDir(MOTOKO_DIR)
    echo "Changed to directory: ", getCurrentDir()
    runCommand("cd backend && mops install")
    var deployResult = execProcess(ICP_PATH & " deploy -y")
    echo "Motoko deploy output: ", deployResult
    check deployResult.contains("Deployed") or deployResult.contains("Creating") or deployResult.contains("Installing") or deployResult.contains("backend")

    for functionName in COMPARE_FUNCTIONS:
      motokoResults[functionName] = callProjectCanisterFunction(MOTOKO_DIR, functionName)

    stopIcpNetwork(MOTOKO_DIR)

    # Nimキャニスターのデプロイ
    ensureIcpNetworkStarted(NIM_DIR)
    setCurrentDir(NIM_DIR)
    echo "Changed to directory: ", getCurrentDir()
    deployResult = execProcess(ICP_PATH & " deploy -y")
    echo "Nim deploy output: ", deployResult
    check deployResult.contains("Deployed") or deployResult.contains("Creating") or deployResult.contains("Installing") or deployResult.contains("backend")

    for functionName in COMPARE_FUNCTIONS:
      nimResults[functionName] = callProjectCanisterFunction(NIM_DIR, functionName)

    stopIcpNetwork(NIM_DIR)
  finally:
    setCurrentDir(originalDir)
    echo "Changed back to directory: ", getCurrentDir()


suite "Candid compare with Motoko tests":
  deploy()

  test "responseNull":
    check rowTest("responseNull")

  test "responseEmpty":
    check rowTest("responseEmpty")
  
  test "bool":
    check rowTest("boolFunc")
  
  test "int":
    check rowTest("intFunc")
  
  test "int8":
    check rowTest("int8Func")

  test "int16":
    check rowTest("int16Func")

  test "int32":
    check rowTest("int32Func")

  test "int64":
    check rowTest("int64Func")

  test "nat":
    check rowTest("natFunc")

  test "nat8":
    check rowTest("nat8Func")

  test "nat16":
    check rowTest("nat16Func")

  test "nat32":
    check rowTest("nat32Func")

  test "nat64":
    check rowTest("nat64Func")
    
  test "float":
    check rowTest("floatFunc")  

  test "text":
    check rowTest("textFunc")

  test "blob":
    check rowTest("blobFunc")

  test "vec nat":
    check rowTest("vecNatFunc")

  test "vec text":
    check rowTest("vecTextFunc")

  test "vec bool":
    check rowTest("vecBoolFunc")

  test "vec int":
    check rowTest("vecIntFunc")

  test "vec vec nat":
    check rowTest("vecVecNatFunc")

  test "vec vec text":
    check rowTest("vecVecTextFunc")

  test "vec vec bool":
    check rowTest("vecVecBoolFunc")

  test "vec vec int":
    check rowTest("vecVecIntFunc")

  test "opt text some":
    check rowTest("optTextSome")

  test "opt text none":
    check rowTest("optTextNone")

  test "opt int some":
    check rowTest("optIntSome")

  test "opt int none":
    check rowTest("optIntNone")

  test "opt nat some":
    check rowTest("optNatSome")

  test "opt nat none":
    check rowTest("optNatNone")

  test "opt float some":
    check rowTest("optFloatSome")

  test "opt float none":
    check rowTest("optFloatNone")

  test "opt bool some":
    check rowTest("optBoolSome")

  test "opt bool none":
    check rowTest("optBoolNone")

  test "record simple":
    check rowTest("recordSimple")

  test "record nested":
    check rowTest("recordNested")

  test "principal":
    check rowTest("principalFunc")

  test "principal anonymous":
    check rowTest("principalAnonymous")

  test "principal canister":
    check rowTest("principalCanister")

  # ===== Variant tests =====
  type Color = enum
    Red
    Green
    Blue

  test "variant color red":
    let motokoResult = callMotokoCanisterFunction("variantColorRed")
    echo "Motoko result: ", motokoResult
    let motokoBytes = hexToBytes(motokoResult)
    let motokoDecoded = decodeCandidMessage(motokoBytes)
    let motokoRequest = newMockRequest(motokoDecoded.values)
    let motokoResponse = motokoRequest.getEnum(0, Color)
    
    let nimResult = callNimCanisterFunction("variantColorRed")
    echo "Nim result:    ", nimResult
    let nimBytes = hexToBytes(nimResult)
    let nimDecoded = decodeCandidMessage(nimBytes)
    let nimRequest = newMockRequest(nimDecoded.values)
    let nimResponse = nimRequest.getEnum(0, Color)
    
    check motokoResponse == nimResponse


  test "variant color green":
    let motokoResult = callMotokoCanisterFunction("variantColorGreen")
    echo "Motoko result: ", motokoResult
    let motokoBytes = hexToBytes(motokoResult)
    let motokoDecoded = decodeCandidMessage(motokoBytes)
    let motokoRequest = newMockRequest(motokoDecoded.values)
    let motokoResponse = motokoRequest.getEnum(0, Color)
    
    let nimResult = callNimCanisterFunction("variantColorGreen")
    echo "Nim result:    ", nimResult
    let nimBytes = hexToBytes(nimResult)
    let nimDecoded = decodeCandidMessage(nimBytes)
    let nimRequest = newMockRequest(nimDecoded.values)
    let nimResponse = nimRequest.getEnum(0, Color)
    
    check motokoResponse == nimResponse


  test "variant color blue":
    let motokoResult = callMotokoCanisterFunction("variantColorBlue")
    echo "Motoko result: ", motokoResult
    let motokoBytes = hexToBytes(motokoResult)
    let motokoDecoded = decodeCandidMessage(motokoBytes)
    let motokoRequest = newMockRequest(motokoDecoded.values)
    let motokoResponse = motokoRequest.getEnum(0, Color)

    let nimResult = callNimCanisterFunction("variantColorBlue")
    echo "Nim result:    ", nimResult
    let nimBytes = hexToBytes(nimResult)
    let nimDecoded = decodeCandidMessage(nimBytes)
    let nimRequest = newMockRequest(nimDecoded.values)
    let nimResponse = nimRequest.getEnum(0, Color)
    
    check motokoResponse == nimResponse

  # ===== Function (ctFunc) tests =====
  # 自キャニスターの query greet() -> text を関数参照として返すケースを比較
  test "func ref: query () -> (text), self greet":
    let motokoResult = callMotokoCanisterFunction("funcRefTextQuery")
    echo "Motoko result: ", motokoResult
    let motokoBytes = motokoResult.toBytes()
    let motokoDecoded = decodeCandidMessage(motokoBytes)
    let motokoRequest = newMockRequest(motokoDecoded.values)
    let motokoFunc = motokoRequest.getFunc(0)
    echo "Motoko func: ", motokoFunc.methodName

    let nimResult = callNimCanisterFunction("funcRefTextQuery")
    echo "Nim result:    ", nimResult
    let nimBytes = nimResult.toBytes()
    let nimDecoded = decodeCandidMessage(nimBytes)
    let nimRequest = newMockRequest(nimDecoded.values)
    let nimFunc = nimRequest.getFunc(0)
    echo "Nim func: ", nimFunc.methodName

    check motokoFunc.methodName == nimFunc.methodName
    check motokoFunc.args == nimFunc.args
    check motokoFunc.returns == nimFunc.returns
