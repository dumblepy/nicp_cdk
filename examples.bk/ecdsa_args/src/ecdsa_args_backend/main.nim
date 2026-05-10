import std/strutils
import std/options
import std/tables
import std/sequtils  # mapItのために追加
import ../../../../src/nicp_cdk

type
  EcdsaCurve* {.pure.} = enum
    secp256k1 = 0
    secp256r1 = 1


proc ecdsaPublicKeyResponse() {.query.} =
  let response = %*{
    "canister_id": Principal.fromText("bkyz2-fmaaa-aaaaa-qaaaq-cai").some(),
    "derivation_path": @[Msg.caller().bytes],
    "key_id": %*{
      "curve": EcdsaCurve.secp256k1,
      "name": "dfx_test_key"
    }
  }
  reply(response)


proc ecdsaSignResponse() {.query.} =
  let response = %*{
    "message_hash": "hello world".toBlob(),
    "derivation_path": @[Msg.caller().bytes],
    "key_id": %*{
      "curve": EcdsaCurve.secp256k1,
      "name": "dfx_test_key"
    }
  }
  reply(response)