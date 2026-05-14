## Private KV 統合テスト向け: @dfinity/vetkeys 0.4.x と同様の手順で
## transport 秘密鍵・encrypted vetkey から対称鍵を導出し AES-256-GCM で保護する。
## 仕様は `docs/ja/refarence/vetkd_overview.md` に準拠。

import std/[strutils, sysrand]

import rustcrypto/algorithm/aesgcm
import rustcrypto/algorithm/bls
import rustcrypto/algorithm/hkdf

const
  EncryptedVetKeyLen = 48 + 96 + 48
  VetKeyC3Offset = 48 + 96
  Aes256KeyBytes = 32
  AesNonceLen = 12
  AesTagLen = 16

template assignFromOpenArray[N: static int](dest: var array[N, byte]; src: openArray[byte]; srcOffset: Natural) =
  ## `src[srcOffset ..< srcOffset + N]` を `dest` にコピーする（境界は呼び出し側で保証）。
  for i in 0 ..< N:
    dest[i] = src[srcOffset + i]

proc bytesToHexLower*(b: openArray[byte]): string =
  result = newStringOfCap(b.len * 2)
  for x in b:
    result.add(x.toHex(2).toLowerAscii)

proc hexToBytesStrict*(hex: string): seq[byte] =
  var cleaned = hex.strip().replace(" ", "").replace("\n", "").replace("\t", "")
  if cleaned.len >= 2 and cleaned[0] == '0' and (cleaned[1] == 'x' or cleaned[1] == 'X'):
    cleaned = cleaned[2 ..^ 1]
  if cleaned.len == 0:
    return @[]
  if cleaned.len mod 2 != 0:
    raise newException(ValueError, "hex string must have even length")
  result = newSeq[byte](cleaned.len div 2)
  for i in 0 ..< result.len:
    let start = i * 2
    result[i] = byte(parseHexInt(cleaned[start ..< start + 2]))

proc toBinaryString*(b: openArray[byte]): string =
  result = newString(b.len)
  for i in 0 ..< b.len:
    result[i] = char(b[i])

proc blsPrivateKeyFromBytes*(b: openArray[byte]): BlsPrivateKey =
  if b.len != BlsPrivateKey.len:
    raise newException(ValueError, "transport secret must be " & $BlsPrivateKey.len & " bytes")
  assignFromOpenArray(result, b, 0)

proc vetkeyG1FromEncrypted*(transportSecret: BlsPrivateKey; encryptedKey: openArray[byte]): BlsG1Compressed =
  if encryptedKey.len != EncryptedVetKeyLen:
    raise newException(
      ValueError,
      "encrypted vetkey must be " & $EncryptedVetKeyLen & " bytes, got " & $encryptedKey.len,
    )
  var c1, c3: BlsG1Compressed
  assignFromOpenArray(c1, encryptedKey, 0)
  assignFromOpenArray(c3, encryptedKey, VetKeyC3Offset)
  var sk: BlsScalar
  assignFromOpenArray(sk, transportSecret, 0)
  let c1Sk = Bls.g1Mul(c1, sk)
  Bls.g1Add(c3, Bls.g1Neg(c1Sk))

proc aes256KeyFromVetKeyG1*(vetKeyG1: BlsG1Compressed; domainSep: string): Aes256GcmKey =
  let ikm = toBinaryString(vetKeyG1)
  let okm = hkdfSha256Derive(salt = "", ikm, domainSep, Aes256KeyBytes)
  for i in 0 ..< Aes256KeyBytes:
    result[i] = okm[i]

proc generateVetkeyTransportKeyPair*(): tuple[transportSecretHex: string, transportPublicHex: string] =
  let sk = Bls.generatePrivateKey()
  let pk = Bls.publicKey(sk)
  (bytesToHexLower(sk), bytesToHexLower(pk))

proc vetkeyEncryptMessage*(
    transportSecretHex, encryptedKeyHex: string; plaintext: openArray[byte]; domainSep: string,
): seq[byte] =
  let sk = blsPrivateKeyFromBytes(hexToBytesStrict(transportSecretHex))
  let enc = hexToBytesStrict(encryptedKeyHex)
  let vetG1 = vetkeyG1FromEncrypted(sk, enc)
  let aesKey = aes256KeyFromVetKeyG1(vetG1, domainSep)
  var nonce: Aes256GcmNonce
  if not urandom(nonce):
    raise newException(IOError, "urandom failed for AES-GCM nonce")
  let (ct, tag) = aes256gcmEncrypt(aesKey, nonce, plaintext, [])
  result = newSeq[byte](nonce.len + ct.len + tag.len)
  var off = 0
  for i in 0 ..< nonce.len:
    result[off + i] = nonce[i]
  off += nonce.len
  for i in 0 ..< ct.len:
    result[off + i] = ct[i]
  off += ct.len
  for i in 0 ..< tag.len:
    result[off + i] = tag[i]

proc vetkeyDecryptMessage*(
    transportSecretHex, encryptedKeyHex: string; ciphertext: openArray[byte]; domainSep: string,
): seq[byte] =
  const minLen = AesNonceLen + AesTagLen
  if ciphertext.len < minLen:
    raise newException(ValueError, "ciphertext too short")
  let sk = blsPrivateKeyFromBytes(hexToBytesStrict(transportSecretHex))
  let enc = hexToBytesStrict(encryptedKeyHex)
  let vetG1 = vetkeyG1FromEncrypted(sk, enc)
  let aesKey = aes256KeyFromVetKeyG1(vetG1, domainSep)
  var nonce: Aes256GcmNonce
  assignFromOpenArray(nonce, ciphertext, 0)
  var tag: Aes256GcmTag
  let bodyLen = ciphertext.len - AesNonceLen - AesTagLen
  assignFromOpenArray(tag, ciphertext, Natural(AesNonceLen + bodyLen))
  var body = newSeq[byte](bodyLen)
  for i in 0 ..< bodyLen:
    body[i] = ciphertext[AesNonceLen + i]
  aes256gcmDecrypt(aesKey, nonce, body, tag, [])
