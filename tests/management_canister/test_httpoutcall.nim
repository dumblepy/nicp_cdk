discard """
  cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/management_canister/test_httpoutcall.nim

import std/unittest
import std/osproc
import std/strutils
import std/os
import icp_network

const
  ICP_PATH = "icp"
  HTTP_OUTCALL_NIM_DIR = "/application/examples/http_outcall/nim"
  HTTP_OUTCALL_MOTOKO_DIR = "/application/examples/http_outcall/motoko"
  CANISTER_NAME = "backend"

proc callCanisterFunction(
  projectDir: string,
  canisterName: string,
  functionName: string,
  args: string = "",
  isQuery: bool = false,
  outputRaw: bool = false
): string =
  ensureIcpNetworkStarted(projectDir)
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let queryFlag = if isQuery: " --query" else: ""
    let outputFlag = if outputRaw: " --output candid" else: ""
    let command = if args == "":
      ICP_PATH & " canister call" & queryFlag & outputFlag & " " & canisterName & " " & functionName & " '()'"
    else:
      ICP_PATH & " canister call" & queryFlag & outputFlag & " " & canisterName & " " & functionName & " '(" & args & ")'"
    echo command
    execProcess(command).strip()
  finally:
    setCurrentDir(originalDir)

proc deploy(projectDir: string, canisterName: string) =
  ensureIcpNetworkStarted(projectDir)
  let originalDir = getCurrentDir()
  try:
    setCurrentDir(projectDir)
    let deployResult = execProcess(ICP_PATH & " deploy -y")
    check deployResult.contains("Deployed") or deployResult.contains("Creating") or
          deployResult.contains("Installing") or deployResult.contains(canisterName)
  finally:
    setCurrentDir(originalDir)


suite "Deploy Tests":
  test "Deploy HTTP outcall canisters":
    deploy(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME)
    deploy(HTTP_OUTCALL_MOTOKO_DIR, CANISTER_NAME)
    sleep(2000)


suite "HTTP Outcall Query Tests":
  test "httpRequestArgs returns request config":
    let result = callCanisterFunction(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME, "httpRequestArgs", isQuery = true)
    echo result
    check result.contains("httpbin.org/get") or result.contains("httpbin.org")

  test "transformFunc returns function reference":
    let result = callCanisterFunction(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME, "transformFunc", isQuery = true)
    echo result
    let lower = result.toLowerAscii()
    check lower.contains("func") or lower.contains("transform")

  test "transformBody returns transform record":
    let result = callCanisterFunction(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME, "transformBody", isQuery = true)
    echo result
    let lower = result.toLowerAscii()
    check lower.contains("function") or lower.contains("context") or lower.contains("record")


suite "HTTP Outcall Update Tests":
  test "get_httpbin returns httpbin response or error":
    let result = callCanisterFunction(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME, "get_httpbin")
    echo result
    let lower = result.toLowerAscii()
    check lower.contains("httpbin") or lower.contains("reject") or lower.contains("failed")

  test "post_httpbin returns httpbin response or error":
    let result = callCanisterFunction(HTTP_OUTCALL_NIM_DIR, CANISTER_NAME, "post_httpbin")
    echo result
    let lower = result.toLowerAscii()
    check lower.contains("httpbin") or lower.contains("reject") or lower.contains("failed")
