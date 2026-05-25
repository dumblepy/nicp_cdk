import { TransportSecretKey, VetKey } from "@dfinity/vetkeys";
import { bls12_381 } from "@noble/curves/bls12-381";

/** `tests/management_canister/test_vetkey.nim` の Private KV シナリオと同じドメイン分離ラベル */
export const PRIVATE_KV_DOMAIN_SEP = "private-kv-v1";

export function hexToBytes(hex: string): Uint8Array {
  const trimmed = hex.trim().replace(/^0x/i, "").replace(/\s+/g, "");
  if (trimmed.length === 0) {
    return new Uint8Array();
  }
  if (trimmed.length % 2 !== 0) {
    throw new Error("hex string must have even length");
  }
  const bytes = new Uint8Array(trimmed.length / 2);
  for (let i = 0; i < trimmed.length; i += 2) {
    bytes[i / 2] = Number.parseInt(trimmed.slice(i, i + 2), 16);
  }
  return bytes;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function generateTransportKeyPair(): {
  transportSecretHex: string;
  transportPublicHex: string;
} {
  const transportSecret = TransportSecretKey.random();
  return {
    transportSecretHex: bytesToHex(transportSecret.serialize()),
    transportPublicHex: bytesToHex(transportSecret.publicKeyBytes()),
  };
}

async function derivedKeyMaterialFromEncryptedKey(
  transportSecretHex: string,
  encryptedVetkeyHex: string,
) {
  const transportSecret = TransportSecretKey.deserialize(
    hexToBytes(transportSecretHex),
  );
  const encryptedKeyBytes = hexToBytes(encryptedVetkeyHex);
  const c1 = bls12_381.G1.Point.fromHex(encryptedKeyBytes.slice(0, 48));
  const c3 = bls12_381.G1.Point.fromHex(
    encryptedKeyBytes.slice(48 + 96),
  );
  const sk = bls12_381.G1.Point.Fn.fromBytes(transportSecret.serialize());
  const vetKey = new VetKey(c3.subtract(c1.multiply(sk)));
  return await vetKey.asDerivedKeyMaterial();
}

export async function encryptPlaintextWithVetkey(
  transportSecretHex: string,
  encryptedVetkeyHex: string,
  plaintext: Uint8Array,
  domainSep: string,
): Promise<Uint8Array> {
  const derivedKeyMaterial = await derivedKeyMaterialFromEncryptedKey(
    transportSecretHex,
    encryptedVetkeyHex,
  );
  return await derivedKeyMaterial.encryptMessage(plaintext, domainSep);
}

export async function decryptCiphertextWithVetkey(
  transportSecretHex: string,
  encryptedVetkeyHex: string,
  ciphertext: Uint8Array,
  domainSep: string,
): Promise<Uint8Array> {
  const derivedKeyMaterial = await derivedKeyMaterialFromEncryptedKey(
    transportSecretHex,
    encryptedVetkeyHex,
  );
  return await derivedKeyMaterial.decryptMessage(ciphertext, domainSep);
}
