## Ethereum Signature Module
## 
## This module provides Ethereum-specific signature operations with 0x prefixes.
## It handles Ethereum address creation, signature verification with addresses,
## and EIP-compliant message hashing for Web3 applications.

import rustcrypto/algorithm/common
import rustcrypto/algorithm/ffi
import rustcrypto/algorithm/secp256k1
import rustcrypto/algorithm/sha3
import rustcrypto/ethereum
import ./hex_bytes

type
  EcdsaVerificationError* = object of CatchableError
  SignatureFormatError* = object of CatchableError
  EthereumConversionError* = object of CatchableError

const
  Secp256k1FieldPrime: array[8, uint32] = [
    0xFFFFFC2Fu32,
    0xFFFFFFFE'u32,
    0xFFFFFFFF'u32,
    0xFFFFFFFF'u32,
    0xFFFFFFFF'u32,
    0xFFFFFFFF'u32,
    0xFFFFFFFF'u32,
    0xFFFFFFFF'u32,
  ]
  ## (p + 1) / 4 for secp256k1 (big-endian bytes). Used for y = sqrt(x^3+7) via modPow.
  secp256k1SqrtExponent: array[32, uint8] = [
    0x3f'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8,
    0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8,
    0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8,
    0xff'u8, 0xff'u8, 0xff'u8, 0xff'u8, 0xbf'u8, 0xff'u8, 0xff'u8, 0x0c'u8,
  ]

proc cptr(data: openArray[byte]): ptr uint8 =
  if data.len == 0:
    nil
  else:
    cast[ptr uint8](unsafeAddr data[0])


proc toFixedArray[T](data: openArray[byte]): T =
  doAssert data.len == result.len
  for i in 0..<data.len:
    result[i] = data[i]


proc toSeqBytes(data: openArray[byte]): seq[uint8] =
  result = newSeq[uint8](data.len)
  for i in 0..<data.len:
    result[i] = data[i]


when defined(wasi) or defined(rustcryptoWasi):
  ## LTO (-flto) + small-field inlining on wasm32-wasip1 has been observed to break
  ## uint64-heavy limb math; keep these procs outlined for correct secp256k1 decompression.
  {.push noinline.}

proc normalizeWords(words: openArray[uint32]): seq[uint32] =
  result = @[]
  for word in words:
    result.add(word)
  while result.len > 1 and result[^1] == 0'u32:
    discard result.pop()
  if result.len == 0:
    result.add(0'u32)


proc padField(words: openArray[uint32]): seq[uint32] =
  let normalized = normalizeWords(words)
  result = newSeq[uint32](8)
  for i in 0..<min(normalized.len, 8):
    result[i] = normalized[i]


proc cmpWords(a, b: openArray[uint32]): int =
  let left = normalizeWords(a)
  let right = normalizeWords(b)
  if left.len != right.len:
    return if left.len < right.len: -1 else: 1

  for i in countdown(left.len - 1, 0):
    if left[i] != right[i]:
      return if left[i] < right[i]: -1 else: 1
  0


proc addWords(a, b: openArray[uint32]): seq[uint32] =
  let maxLen = max(a.len, b.len)
  result = newSeq[uint32](maxLen + 1)
  var carry: uint64 = 0
  for i in 0..<maxLen:
    let av = if i < a.len: uint64(a[i]) else: 0
    let bv = if i < b.len: uint64(b[i]) else: 0
    let sum = av + bv + carry
    result[i] = uint32(sum and 0xFFFFFFFF'u64)
    carry = sum shr 32
  result[maxLen] = uint32(carry)
  result = normalizeWords(result)


proc subWords(a, b: openArray[uint32]): seq[uint32] =
  if cmpWords(a, b) < 0:
    raise newException(EthereumConversionError, "internal field subtraction underflow")
  result = newSeq[uint32](a.len)
  var borrow: uint64 = 0
  for i in 0..<a.len:
    let av = uint64(a[i])
    let bv = if i < b.len: uint64(b[i]) else: 0
    let subtrahend = bv + borrow
    if av >= subtrahend:
      result[i] = uint32(av - subtrahend)
      borrow = 0
    else:
      result[i] = uint32((av + 0x1_0000_0000'u64) - subtrahend)
      borrow = 1
  result = normalizeWords(result)


proc mulSmall(a: openArray[uint32], k: uint32): seq[uint32] =
  if a.len == 0:
    return @[0'u32]

  result = newSeq[uint32](a.len + 1)
  var carry: uint64 = 0
  for i in 0..<a.len:
    let product = uint64(a[i]) * uint64(k) + carry
    result[i] = uint32(product and 0xFFFFFFFF'u64)
    carry = product shr 32
  result[a.len] = uint32(carry)
  result = normalizeWords(result)


proc shiftLeft32(a: openArray[uint32]): seq[uint32] =
  result = newSeq[uint32](a.len + 1)
  for i in 0..<a.len:
    result[i + 1] = a[i]
  result = normalizeWords(result)


proc mulWords(a, b: openArray[uint32]): seq[uint32] =
  if a.len == 0 or b.len == 0:
    return @[0'u32]

  result = newSeq[uint32](a.len + b.len + 1)
  for i in 0..<a.len:
    var carry: uint64 = 0
    for j in 0..<b.len:
      let idx = i + j
      let accum = uint64(result[idx]) + uint64(a[i]) * uint64(b[j]) + carry
      result[idx] = uint32(accum and 0xFFFFFFFF'u64)
      carry = accum shr 32

    var idx = i + b.len
    while carry > 0:
      let accum = uint64(result[idx]) + carry
      result[idx] = uint32(accum and 0xFFFFFFFF'u64)
      carry = accum shr 32
      inc idx
  result = normalizeWords(result)


proc reduceModP(words: openArray[uint32]): seq[uint32] =
  var cur = normalizeWords(words)

  while cur.len > 8:
    let low = cur[0..<8]
    let high = cur[8..^1]
    var folded = addWords(low, mulSmall(high, 977'u32))
    folded = addWords(folded, shiftLeft32(high))
    cur = normalizeWords(folded)

  while cmpWords(cur, Secp256k1FieldPrime) >= 0:
    cur = subWords(cur, Secp256k1FieldPrime)

  result = padField(cur)


proc modMul(a, b: openArray[uint32]): seq[uint32] =
  reduceModP(mulWords(a, b))


proc modPow(base: openArray[uint32], exponent: openArray[uint8]): seq[uint32] =
  var resultWords = padField([1'u32])
  let baseWords = padField(base)

  for exponentByte in exponent:
    for bit in countdown(7, 0):
      resultWords = modMul(resultWords, resultWords)
      if ((exponentByte shr bit) and 1'u8) == 1'u8:
        resultWords = modMul(resultWords, baseWords)

  result = padField(resultWords)

when defined(wasi) or defined(rustcryptoWasi):
  {.pop.}


proc bytesToFieldWords(data: openArray[byte]): seq[uint32] =
  if data.len != 32:
    raise newException(EthereumConversionError, "field element must be 32 bytes")

  result = newSeq[uint32](8)
  for i in 0..<8:
    let base = data.len - ((i + 1) * 4)
    result[i] =
      (uint32(data[base]) shl 24) or
      (uint32(data[base + 1]) shl 16) or
      (uint32(data[base + 2]) shl 8) or
      uint32(data[base + 3])


proc fieldWordsToBytes(words: openArray[uint32]): seq[uint8] =
  let normalized = padField(words)
  result = newSeq[uint8](32)
  for i in 0..<8:
    let word = normalized[7 - i]
    result[i * 4] = uint8((word shr 24) and 0xFF)
    result[i * 4 + 1] = uint8((word shr 16) and 0xFF)
    result[i * 4 + 2] = uint8((word shr 8) and 0xFF)
    result[i * 4 + 3] = uint8(word and 0xFF)


proc fieldParity(words: openArray[uint32]): bool =
  let normalized = normalizeWords(words)
  (normalized[0] and 1'u32) == 1'u32


proc ensureUncompressedPublicKey(publicKey: seq[uint8]): secp256k1.Secp256k1UncompressedPublicKey =
  if publicKey.len != 65 or publicKey[0] != 0x04'u8:
    raise newException(EthereumConversionError, "invalid uncompressed public key format")
  result = toFixedArray[Secp256k1UncompressedPublicKey](publicKey)


proc ensureCompressedPublicKey(publicKey: seq[uint8]): secp256k1.Secp256k1CompressedPublicKey =
  if publicKey.len != 33:
    raise newException(EthereumConversionError, "ICP public key must be 33 bytes (compressed format)")
  result = toFixedArray[Secp256k1CompressedPublicKey](publicKey)


proc ensureMessageDigest(messageHash: seq[uint8]): secp256k1.Secp256k1MessageDigest =
  if messageHash.len != 32:
    raise newException(EcdsaVerificationError, "message hash must be 32 bytes")
  result = toFixedArray[Secp256k1MessageDigest](messageHash)


proc ensureCompactSignature(signature: seq[uint8]): secp256k1.Secp256k1Signature =
  if signature.len != 64:
    raise newException(SignatureFormatError, "ICP signature must be 64 bytes")
  result = toFixedArray[Secp256k1Signature](signature)


proc recoverableSignatureFromCompact(signature: openArray[byte], recoveryId: uint8): secp256k1.Secp256k1RecoverableSignature =
  if signature.len != 64:
    raise newException(SignatureFormatError, "ICP signature must be 64 bytes")
  if recoveryId > 3'u8:
    raise newException(SignatureFormatError, "recovery id must be between 0 and 3")

  var raw = newSeq[uint8](65)
  for i in 0..<64:
    raw[i] = signature[i]
  raw[64] = recoveryId
  result = toFixedArray[Secp256k1RecoverableSignature](raw)


proc toEvmHexString*(data: seq[uint8], prefix: bool = true): string =
  ## Convert byte sequence to hex string with 0x prefix for Ethereum compatibility
  let hexStr = bytesToHexString(data)
  if prefix:
    return "0x" & hexStr
  else:
    return hexStr


proc decompressPublicKey*(compressedKey: seq[uint8]): seq[uint8] =
  ## Decompress a compressed secp256k1 public key (33 bytes) to uncompressed format (65 bytes)
  if compressedKey.len != 33:
    raise newException(EthereumConversionError, "Compressed key must be 33 bytes")
  if compressedKey[0] != 0x02'u8 and compressedKey[0] != 0x03'u8:
    raise newException(EthereumConversionError, "compressed key must start with 0x02 or 0x03")

  try:
    let xWords = bytesToFieldWords(compressedKey[1..^1])
    let xSquared = modMul(xWords, xWords)
    let xCubed = modMul(xSquared, xWords)
    let rhs = reduceModP(addWords(xCubed, @[7'u32]))
    let yWords = modPow(rhs, secp256k1SqrtExponent)

    if cmpWords(modMul(yWords, yWords), rhs) != 0:
      let head = toHexString(compressedKey[0 ..< min(8, compressedKey.len)])
      raise newException(EthereumConversionError,
        "compressed key is not on the secp256k1 curve (len=" & $compressedKey.len &
        ", head=" & head & "); expected SEC1 compressed secp256k1 from ICP ecdsa_public_key")

    var finalY = yWords
    let yIsOdd = fieldParity(finalY)
    let shouldBeOdd = compressedKey[0] == 0x03'u8
    if yIsOdd != shouldBeOdd:
      finalY = subWords(Secp256k1FieldPrime, finalY)

    result = newSeq[uint8](65)
    result[0] = 0x04'u8
    let xBytes = fieldWordsToBytes(xWords)
    let yBytes = fieldWordsToBytes(finalY)
    for i in 0..<32:
      result[i + 1] = xBytes[i]
      result[i + 33] = yBytes[i]
  except CatchableError as e:
    raise newException(EthereumConversionError, e.msg)
    # if e of EthereumConversionError:
    #   raise newException(EthereumConversionError, e.msg)
    # else:
    #   raise newException(EthereumConversionError, "secp256k1 decompression failed: " & e.msg)


func keccak256Hash*(data: string): seq[uint8] =
  ## Hash string data using Keccak-256 with EIP-191 format
  ## This follows the Ethereum personal_sign standard: "\x19Ethereum Signed Message:\n" + length + message
  let personalMessage = "\x19Ethereum Signed Message:\n" & $data.len & data
  let hash = keccak256(personalMessage)
  result = newSeq[uint8](hash.len)
  for i, b in hash:
    result[i] = b


proc parseSignature*(signatureHex: string): tuple[r: seq[uint8], s: seq[uint8], v: uint8] =
  ## Parse signature hex string into r, s, v components
  try:
    let sigBytes = hexToBytes(signatureHex)
    if sigBytes.len != 64 and sigBytes.len != 65:
      raise newException(SignatureFormatError, "Invalid signature length")

    result.r = newSeq[uint8](32)
    result.s = newSeq[uint8](32)
    for i in 0..<32:
      result.r[i] = sigBytes[i]
      result.s[i] = sigBytes[32 + i]
    result.v = if sigBytes.len == 65: sigBytes[64] else: 27'u8
  except CatchableError as e:
    if e of SignatureFormatError:
      raise
    raise newException(SignatureFormatError, e.msg)


proc recoverPublicKeyFromSignature*(
  messageHash: seq[uint8],
  signatureHex: string,
  recoveryId: uint8
): seq[uint8] =
  ## Recover public key from signature using RustCrypto secp256k1.
  try:
    if messageHash.len != 32:
      raise newException(EcdsaVerificationError, "message hash must be 32 bytes")

    let (r, s, _) = parseSignature(signatureHex)
    let digest = ensureMessageDigest(messageHash)
    let recoverableSig = recoverableSignatureFromCompact(r & s, recoveryId)
    var publicKey = newSeq[uint8](65)
    let status = secp256k1EcdsaRecoverPublicKeyRaw(
      cptr(digest),
      csize_t(digest.len),
      cptr(recoverableSig),
      csize_t(recoverableSig.len),
      cast[ptr uint8](addr publicKey[0]),
      csize_t(publicKey.len),
      Secp256k1PublicKeyFormatUncompressed,
    )
    case status
    of RustCryptoOk:
      return publicKey
    of RustCryptoErrVerificationFailed:
      raise newException(EcdsaVerificationError, "Failed to recover public key")
    of RustCryptoErrNullOutput,
       RustCryptoErrOutputTooShort,
       RustCryptoErrNullInputWithData,
       RustCryptoErrInvalidMessageDigest,
       RustCryptoErrInvalidSignature,
       RustCryptoErrInvalidPublicKeyFormat,
       RustCryptoErrPanic:
      raise newException(EcdsaVerificationError, "Recovery failed with status " & $status)
    else:
      raise newException(EcdsaVerificationError, "Recovery failed with unexpected status " & $status)
  except CatchableError as e:
    if e of SignatureFormatError or e of EcdsaVerificationError:
      raise
    raise newException(EcdsaVerificationError, e.msg)


proc publicKeyToEthereumAddress*(pubKey: seq[uint8]): string =
  ## Convert public key (65 bytes uncompressed) to Ethereum address
  let uncompressed = ensureUncompressedPublicKey(pubKey)
  return $Ethereum.address(uncompressed)


proc icpPublicKeyToEvmAddress*(icpPublicKey: seq[uint8]): string =
  ## Convert ICP ECDSA public key to Ethereum address.
  ## Accepts SEC1 compressed (33 bytes, prefix 0x02/0x03) per IC spec, or uncompressed (65 bytes, 0x04).
  ## Use only the ``public_key`` blob from ``ecdsa_public_key``; do not concatenate ``chain_code``.
  if icpPublicKey.len == 65 and icpPublicKey[0] == 0x04'u8:
    return publicKeyToEthereumAddress(icpPublicKey)
  if icpPublicKey.len != 33:
    raise newException(
      EthereumConversionError,
      "ICP ECDSA public key must be 33 bytes (SEC1 compressed) or 65 bytes (SEC1 uncompressed, 0x04); got " &
        $icpPublicKey.len &
        " bytes. Use only the `public_key` field from ecdsa_public_key, not `chain_code`.",
    )
  let compressed = ensureCompressedPublicKey(icpPublicKey)
  let uncompressed = decompressPublicKey(toSeqBytes(compressed))
  return publicKeyToEthereumAddress(uncompressed)


proc verifyEthereumSignatureWithAddress*(
  ethereumAddress: string,
  message: string,
  signatureHex: string
): bool =
  ## Verify Ethereum signature using address (without needing the public key)
  ## Uses EIP-191 format for message hashing by default
  try:
    let (r, s, v) = parseSignature(signatureHex)
    let signature = EthereumSignature(
      r: toFixedArray[array[32, byte]](r),
      s: toFixedArray[array[32, byte]](s),
      v: v,
    )
    let addressBytes = hexToBytes(ethereumAddress)
    if addressBytes.len != 20:
      return false
    let walletAddress = toFixedArray[EthereumAddress](addressBytes)
    return Ethereum.verifyPersonalMessage(message, walletAddress, signature)
  except CatchableError:
    return false


proc convertIcpSignatureToEthereum*(
  icpSignature: seq[uint8],
  messageHash: seq[uint8],
  publicKey: seq[uint8]
): string =
  ## Convert ICP Management Canister signature (64 bytes, r+s) to Ethereum format (65 bytes, r+s+v)
  ## This function determines the correct recovery ID (v) and returns the full Ethereum signature
  if icpSignature.len != 64:
    raise newException(SignatureFormatError, "ICP signature must be 64 bytes")
  if messageHash.len != 32:
    raise newException(EcdsaVerificationError, "message hash must be 32 bytes")

  let digest = ensureMessageDigest(messageHash)
  let compactSignature = ensureCompactSignature(icpSignature)

  for rawRecoveryId in [0'u8, 1'u8]:
    let recoverableSignature = recoverableSignatureFromCompact(compactSignature, rawRecoveryId)
    let isValid =
      case publicKey.len
      of 33:
        Secp256k1.verifyRecoverable(
          digest,
          toFixedArray[Secp256k1CompressedPublicKey](publicKey),
          recoverableSignature,
        )
      of 65:
        Secp256k1.verifyRecoverable(
          digest,
          toFixedArray[Secp256k1UncompressedPublicKey](publicKey),
          recoverableSignature,
        )
      else:
        raise newException(EcdsaVerificationError, "public key must be 33 or 65 bytes")

    if isValid:
      var ethSignature = newSeq[uint8](65)
      for i in 0..<64:
        ethSignature[i] = compactSignature[i]
      ethSignature[64] = 27'u8 + rawRecoveryId
      return toEvmHexString(ethSignature, true)

  var fallbackSignature = newSeq[uint8](65)
  for i in 0..<64:
    fallbackSignature[i] = compactSignature[i]
  fallbackSignature[64] = 27'u8
  return toEvmHexString(fallbackSignature, true)
