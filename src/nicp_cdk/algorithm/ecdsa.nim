## ECDSA Signature Verification Module
## 
## This module provides pure ECDSA cryptographic operations using RustCrypto secp256k1.
## It handles raw byte operations without 0x prefixes for low-level cryptographic processing.
## For Ethereum-specific operations with 0x prefixes, use the ethereum.nim module.

import rustcrypto/algorithm/secp256k1
import rustcrypto/algorithm/sha3
import ./hex_bytes
import ../ic_api

type
  EcdsaError* = object of ValueError


func keccak256Hash*(message: string): seq[uint8] =
  ## Calculate Keccak-256 hash of message.
  let hash = keccak256(message)
  result = newSeq[uint8](hash.len)
  for i, b in hash:
    result[i] = b


proc toFixedArray[T](data: openArray[byte]): T =
  doAssert data.len == result.len
  for i in 0..<data.len:
    result[i] = data[i]


proc validateSignatureWithSecp256k1*(
  messageHash: seq[uint8],
  signatureBytes: seq[uint8], 
  publicKeyBytes: seq[uint8]
): bool =
  ## Validate signature using RustCrypto secp256k1.
  try:
    if messageHash.len != 32 or signatureBytes.len != 64:
      return false

    let digest = toFixedArray[Secp256k1MessageDigest](messageHash)
    let signature = toFixedArray[Secp256k1Signature](signatureBytes)

    case publicKeyBytes.len
    of 33:
      let publicKey = toFixedArray[Secp256k1CompressedPublicKey](publicKeyBytes)
      return Secp256k1.verify(digest, publicKey, signature)
    of 65:
      let publicKey = toFixedArray[Secp256k1UncompressedPublicKey](publicKeyBytes)
      return Secp256k1.verify(digest, publicKey, signature)
    else:
      return false

  except CatchableError:
    return false


proc verifySignatureWithSecp256k1*(
  message: string,
  signatureHex: string,
  publicKeyHex: string
): bool =
  ## Verify signature using RustCrypto secp256k1 with hex inputs.
  try:
    let messageHash = keccak256Hash(message)
    let signatureBytes = hexToBytes(signatureHex)
    let publicKeyBytes = hexToBytes(publicKeyHex)
    return validateSignatureWithSecp256k1(messageHash, signatureBytes, publicKeyBytes)

  except CatchableError:
    return false
