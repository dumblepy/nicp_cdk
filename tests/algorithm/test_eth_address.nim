discard """
  cmd: "nim c --skipUserCfg $file"
"""
# nim c -r --skipUserCfg tests/algorithm/test_eth_address.nim

import std/unittest
import std/strutils
import std/times
import ../../src/nicp_cdk/algorithm/ethereum
import rustcrypto/algorithm/secp256k1
import rustcrypto/ethereum

proc toSeqBytes(data: openArray[byte]): seq[uint8] =
  result = newSeq[uint8](data.len)
  for i in 0..<data.len:
    result[i] = data[i]


proc toFixedArray[T](data: openArray[byte]): T =
  doAssert data.len == result.len
  for i in 0..<data.len:
    result[i] = data[i]

suite "Ethereum Address Conversion Tests":
  
  test "toEvmHexString function":
    let testData = @[0x12'u8, 0x34, 0x56, 0xAB, 0xCD, 0xEF]
    
    # Test with prefix
    check toEvmHexString(testData, true) == "0x123456abcdef"
    
    # Test without prefix
    check toEvmHexString(testData, false) == "123456abcdef"
    
    # Test empty data
    check toEvmHexString(@[], true) == "0x"
    check toEvmHexString(@[], false) == ""
  
  test "Real secp256k1 implementation tests":
    let secretKey = Secp256k1.generateSecretKey()
    let icpPubKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    echo "Testing with ICP public key: ", toEvmHexString(icpPubKey)
    let ethAddress = icpPublicKeyToEvmAddress(icpPubKey)
    echo "Generated Ethereum address: ", ethAddress

    check ethAddress.len == 42  # "0x" + 40 characters
    check ethAddress.startsWith("0x")
    check ethAddress == ethAddress.toLowerAscii()
    
    # The address should be the cryptographically correct result
    echo "Real secp256k1 address: ", ethAddress
  
  test "Real secp256k1 decompression":
    let secretKey = Secp256k1.generateSecretKey()
    let compressedKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let uncompressedExpected = toSeqBytes(Secp256k1.publicKeyUncompressed(secretKey))

    let uncompressed = decompressPublicKey(compressedKey)
    check uncompressed == uncompressedExpected
    check uncompressed.len == 65
    check uncompressed[0] == 0x04

  test "keccak256Hash function":
    let message = "Hello, Ethereum!"
    let hash = keccak256Hash(message)
    let expected = Ethereum.personalMessageHash(message)

    check hash.len == 32
    check hash == toSeqBytes(expected)
    check keccak256Hash("") == toSeqBytes(Ethereum.personalMessageHash(""))
    check hash == keccak256Hash(message)
  
  test "parseSignature function":
    # Test valid signature parsing (130 hex chars = 65 bytes)
    let signatureHex = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1b"
    let (r, s, v) = parseSignature(signatureHex)
    
    check r.len == 32
    check s.len == 32
    check v == 0x1b
    
    # Test without 0x prefix
    let signatureHex2 = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1b"
    let (r2, s2, v2) = parseSignature(signatureHex2)
    check r2 == r
    check s2 == s
    check v2 == v
    
    # Test invalid length
    expect(SignatureFormatError):
      discard parseSignature("0x1234")  # Too short
  
  test "publicKeyToEthereumAddress with test keys":
    let secretKey = Secp256k1.generateSecretKey()
    let uncompressedKey = toSeqBytes(Secp256k1.publicKeyUncompressed(secretKey))
    let address = publicKeyToEthereumAddress(uncompressedKey)
    check address.startsWith("0x")
    check address.len == 42  # 0x + 40 hex characters

    expect(EthereumConversionError):
      discard publicKeyToEthereumAddress(newSeq[uint8](64))  # Missing 0x04 prefix

    expect(EthereumConversionError):
      discard publicKeyToEthereumAddress(@[0x03'u8] & newSeq[uint8](64))  # Wrong prefix
  
  test "icpPublicKeyToEvmAddress with sample data":
    let secretKey = Secp256k1.generateSecretKey()
    let icpPubKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let ethAddress = icpPublicKeyToEvmAddress(icpPubKey)

    check ethAddress.startsWith("0x")
    check ethAddress.len == 42

    let hexPart = ethAddress[2..^1]
    for c in hexPart:
      check c in "0123456789abcdef"
    
    echo "Generated Ethereum address: ", ethAddress
  
  test "icpPublicKeyToEvmAddress validation":
    # Test with wrong length
    expect(EthereumConversionError):
      discard icpPublicKeyToEvmAddress(newSeq[uint8](32))  # Too short
    
    expect(EthereumConversionError):
      discard icpPublicKeyToEvmAddress(newSeq[uint8](34))  # Too long

    expect(EthereumConversionError):
      discard icpPublicKeyToEvmAddress(newSeq[uint8](65))  # Wrong: 65 bytes must start with 0x04
    
    # Test with empty sequence
    expect(EthereumConversionError):
      discard icpPublicKeyToEvmAddress(@[])

  test "icpPublicKeyToEvmAddress known ICP compressed public key":
    let pk: seq[uint8] = @[
      2'u8, 184, 241, 143, 103, 71, 137, 127, 190, 154, 216, 182, 115, 172, 131, 115,
      158, 221, 104, 189, 153, 101, 176, 128, 207, 9, 83, 63, 93, 182, 195, 41, 47'u8,
    ]
    check icpPublicKeyToEvmAddress(pk) == "0x491635bc2dbfe8445334f2a2ccc0fd628f6a7afe"
  
  test "convertIcpSignatureToEthereum function":
    let secretKey = Secp256k1.generateSecretKey()
    let message = "convertIcpSignatureToEthereum"
    let messageHash = keccak256Hash(message)
    let publicKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let icpSignature = toSeqBytes(
      Secp256k1.sign(toFixedArray[Secp256k1MessageDigest](messageHash), secretKey)
    )

    let ethSignature = convertIcpSignatureToEthereum(icpSignature, messageHash, publicKey)
    check ethSignature.startsWith("0x")
    check ethSignature.len == 132  # 0x + 130 hex chars = 65 bytes

    expect(SignatureFormatError):
      discard convertIcpSignatureToEthereum(newSeq[uint8](63), messageHash, publicKey)
  
  test "Error handling with real secp256k1":
    # Test invalid length
    expect(EthereumConversionError):
      let invalidKey = @[2'u8, 3]  # Too short
      discard icpPublicKeyToEvmAddress(invalidKey)
    
    # Test invalid prefix for decompression
    expect(EthereumConversionError):
      var invalidKey = newSeq[uint8](33)
      invalidKey[0] = 0x01  # Invalid prefix
      discard decompressPublicKey(invalidKey)


suite "Performance and Consistency Tests":
  test "address consistency":
    let secretKey = Secp256k1.generateSecretKey()
    let icpPubKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let address1 = icpPublicKeyToEvmAddress(icpPubKey)
    let address2 = icpPublicKeyToEvmAddress(icpPubKey)

    check address1 == address2
    echo "Consistent address: ", address1
  
  test "Performance and consistency":
    let secretKey = Secp256k1.generateSecretKey()
    let icpPubKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let addr1 = icpPublicKeyToEvmAddress(icpPubKey)
    let addr2 = icpPublicKeyToEvmAddress(icpPubKey)
    let addr3 = icpPublicKeyToEvmAddress(icpPubKey)

    check addr1 == addr2
    check addr2 == addr3
    
    echo "Consistent address: ", addr1
  
  test "Performance benchmark":
    let secretKey = Secp256k1.generateSecretKey()
    let icpPubKey = toSeqBytes(Secp256k1.publicKeyCompressed(secretKey))
    let iterations = 100  # Reduced for testing
    let startTime = epochTime()
    
    for i in 0..<iterations:
      discard icpPublicKeyToEvmAddress(icpPubKey)
    
    let endTime = epochTime()
    let totalTime = endTime - startTime
    let avgTime = totalTime / iterations.float
    
    echo "Performance: ", iterations, " conversions in ", totalTime.formatFloat(ffDecimal, 4), "s"
    echo "Average time per conversion: ", (avgTime * 1000).formatFloat(ffDecimal, 4), "ms"
    
    # Performance should be reasonable for the pure Nim fallback.
    check avgTime < 0.02  # Less than 20ms per conversion
  
  test "error handling comprehensive":
    expect(EthereumConversionError):
      discard decompressPublicKey(@[])

    expect(SignatureFormatError):
      discard parseSignature("invalid")

    expect(EthereumConversionError):
      discard publicKeyToEthereumAddress(@[0x01'u8] & newSeq[uint8](64)) 
