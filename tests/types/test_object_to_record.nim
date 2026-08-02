discard """
cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/types/test_object_to_record.nim

import std/unittest
import std/options
import std/strutils
import ../../src/nicp_cdk/reply
import ../../src/nicp_cdk/request
import ../../src/nicp_cdk/ic_types/candid_types
import ../../src/nicp_cdk/ic_types/ic_record
import ../../src/nicp_cdk/ic_types/ic_text
import ../../src/nicp_cdk/ic_types/ic_principal
import ../../src/nicp_cdk/ic_types/candid_message/candid_encode
import ../../src/nicp_cdk/ic_types/candid_message/candid_decode


suite("test_object_to_record"):
  test("test_object_to_record"):
    type TestObject = object
      a: uint
      b: string
      c: bool

    let obj = TestObject(a: 1, b: "test", c: true)
    let record = newCandidRecord(obj)
    let encoded = encodeCandidMessage(@[record])
    echo encoded.toString()
    let decoded = decodeCandidMessage(encoded)
    echo decoded
    let request = newMockRequest(decoded.values)
    check request.getRecord(0)["a"].getNat() == 1
    check request.getRecord(0)["b"].getStr() == "test"
    check request.getRecord(0)["c"].getBool() == true

suite("ecdsa"):
  type
    EcdsaCurve {.pure.} = enum
      secp256k1
      secp256r1
    
    EcdsaKeyId = object
      curve: EcdsaCurve
      name: string

  test("ecdsa public key"):
    type EcdsaPublicKey = object
      canister_id: Option[Principal]
      derivation_path: seq[seq[byte]]
      key_id: EcdsaKeyId

    let arg = EcdsaPublicKey(
      canister_id: Principal.managementCanister().some(),
      derivation_path: @[Principal.anonymousUser().bytes],
      key_id: EcdsaKeyId(curve: EcdsaCurve.secp256k1, name: "dfx_test_key")
    )
    let record = newCandidRecord(arg)
    let encoded = encodeCandidMessage(@[record])
    echo encoded.toString()
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getRecord(0)["canister_id"].getOpt().getPrincipal() == Principal.managementCanister()
    check request.getRecord(0)["derivation_path"].getArray().len == 1
    check request.getRecord(0)["derivation_path"][0].getBlob() == Principal.anonymousUser().bytes
    check request.getRecord(0)["key_id"]["curve"].getVariant(EcdsaCurve) == EcdsaCurve.secp256k1
    check request.getRecord(0)["key_id"]["name"].getStr() == "dfx_test_key"

  test("ecdsa signature"):
    type EcdsaSignature = object
      message_hash: seq[byte]
      derivation_path: seq[seq[byte]]
      key_id: EcdsaKeyId

    let arg = EcdsaSignature(
      message_hash: "hello world".toBlob(),
      derivation_path: @[Principal.anonymousUser().bytes],
      key_id: EcdsaKeyId(curve: EcdsaCurve.secp256k1, name: "dfx_test_key")
    )
    let record = newCandidRecord(arg)
    let encoded = encodeCandidMessage(@[record])
    echo encoded.toString()
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
    check request.getRecord(0)["message_hash"].getBlob() == "hello world".toBlob()
    check request.getRecord(0)["derivation_path"].getArray().len == 1
    check request.getRecord(0)["derivation_path"][0].getBlob() == Principal.anonymousUser().bytes
    check request.getRecord(0)["key_id"]["curve"].getVariant(EcdsaCurve) == EcdsaCurve.secp256k1
    check request.getRecord(0)["key_id"]["name"].getStr() == "dfx_test_key"

  test("http outcall request"):
    type
      HttpHeader = ref object
        name: string
        value: string

      HttpMethod {.pure.} = enum
        get = 0
        post = 1
        head = 2

      HttpResponsePayload = ref object
        status: uint
        headers: seq[HttpHeader]
        body: seq[byte]

      TransformArgs = ref object
        context: seq[byte]
        response: HttpResponsePayload

      HttpRequestArgs = ref object
        url: string
        max_response_bytes: Option[uint64]
        headers: seq[HttpHeader]
        body: Option[seq[byte]]
        transform: Option[TransformArgs]
        httpMethod: HttpMethod
        is_replicated: Option[bool]

    let ONE_MINUTE: uint64 = 60
    let start_timestamp: uint64 = 1682978460 # May 1, 2023 22:01:00 GMT
    let host: string = "api.exchange.coinbase.com"
    let url = "https://" & host & "/products/ICP-USD/candles?start=" & $start_timestamp & "&end=" & $start_timestamp & "&granularity=" & $ONE_MINUTE

    let request_headers = @[
      HttpHeader(name: "User-Agent", value: "price-feed")
    ]

    let httpRequest = HttpRequestArgs(
      url: url,
      max_response_bytes: none(uint64), # optional for request
      headers: request_headers,
      body: none(seq[byte]), # optional for request
      httpMethod: HttpMethod.get,
      transform: none(TransformArgs),
      # Toggle this flag to switch between replicated and non-replicated http outcalls.
      is_replicated: some(false)
    )

    let record = newCandidRecord(httpRequest)
    let encoded = encodeCandidMessage(@[record])
    echo encoded.toString()
    let decoded = decodeCandidMessage(encoded)
    let request = newMockRequest(decoded.values)
