discard """
  cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/test_sign_verify.nim

import unittest
import rustcrypto/algorithm/secp256k1
import rustcrypto/algorithm/sha3

suite("sign and verify"):
  test("RustCrypto secp256k1 raw bytes"):
    let secretKey = Secp256k1.generateSecretKey()
    let publicKey = Secp256k1.publicKeyCompressed(secretKey)
    let message = "Hello, World!"
    let messageHash = keccak256(message)
    let signature = Secp256k1.sign(messageHash, secretKey)
    check Secp256k1.verify(messageHash, publicKey, signature)
