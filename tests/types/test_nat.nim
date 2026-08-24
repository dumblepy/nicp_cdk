discard """
cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/types/test_nat.nim

import unittest
import ../../src/nicp_cdk/request
import ../../src/nicp_cdk/ic_types/candid_types
import ../../src/nicp_cdk/ic_types/candid_message/candid_encode
import ../../src/nicp_cdk/ic_types/candid_message/candid_decode


suite "ic_nat tests":
  test("nat"):
    let n = 10.uint
    let candidNat = newCandidNat(n)
    let encoded = encodeCandidMessage(@[candidNat])
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getNat(0) == n

  test("nat8"):
    let n = 10.uint8
    let candidNat8 = newCandidNat8(n)
    let encoded = encodeCandidMessage(@[candidNat8])
    echo "encoded: ", encoded.toString()
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getNat8(0) == n

  test("nat16"):
    let n = 10.uint16
    let candidNat16 = newCandidNat16(n)
    let encoded = encodeCandidMessage(@[candidNat16])
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getNat16(0) == n

  test("nat32"):
    let n = 10.uint32
    let candidNat32 = newCandidNat32(n)
    let encoded = encodeCandidMessage(@[candidNat32])
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getNat32(0) == n

  test("nat32-compatible key accepts nat and nat32"):
    let natRequest = newMockRequest(@[newCandidNat(10'u)])
    let nat32Request = newMockRequest(@[newCandidNat32(10'u32)])
    check natRequest.getNat32Compatible(0) == 10'u32
    check nat32Request.getNat32Compatible(0) == 10'u32

  test("nat64"):
    let n = 10.uint64
    let candidNat64 = newCandidNat64(n)
    let encoded = encodeCandidMessage(@[candidNat64])
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getNat64(0) == n
