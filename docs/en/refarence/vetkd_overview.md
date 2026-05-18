The following is an example of using the low-level vetKD API directly to obtain a per-user AES-GCM key in the browser. Communication and authentication with ICP use `@icp-sdk`; vetKey decryption, verification, and key derivation use the official `@dfinity/vetkeys`. In the ICP JS SDK, `@icp-sdk/core` is the package for talking to the IC, and `@icp-sdk/core/agent` is used to create actors. ([ICP JS SDK Docs][1]) Official vetKey examples also import `DerivedPublicKey`, `TransportSecretKey`, and `EncryptedVetKey` from `@dfinity/vetkeys`. ([internetcomputer.org][2])

## 1. Basic structure of vetKey

A vetKey is a key deterministically derived from the subnet’s threshold master key on ICP using these values. The same `key_id + canister_id + context + input` always yields the same vetKey. The official API states that the same inputs return the same key, and different `input` values produce arbitrarily many distinct keys. ([internetcomputer.org][2])

The management canister exposes these two APIs:

```did
vetkd_derive_key : (record {
  input : blob;
  context : blob;
  transport_public_key : blob;
  key_id : record { curve : vetkd_curve; name : text };
}) -> (record { encrypted_key : blob });

vetkd_public_key : (record {
  canister_id : opt canister_id;
  context : blob;
  key_id : record { curve : vetkd_curve; name : text };
}) -> (record { public_key : blob });
```

Meaning of each field:

| Field                  |                     Who creates it | Secret? | Role                                                                                                                        |
| ---------------------- | ---------------------------------: | -------: | ------------------------------------------------------------------------------------------------------------------------- |
| `key_id`               |                            backend |       no | Which master key to use. Examples: local `dfx_test_key`, mainnet test `test_key_1`, production `key_1`. ([internetcomputer.org][2]) |
| `context`              |                            backend |       no | Domain separating dapp, purpose, user, and scope of authority. In the example: `domain separator + caller principal`.                                                     |
| `input`                |               frontend or backend |       no | Identifier for an individual key. Examples: `"note/default"`, `"file:<uuid>"`. Changing `input` within the same context yields another key.                                                  |
| `transport_public_key` |                           frontend |       no | Ephemeral public key so only the frontend can decrypt the returned vetKey.                                                                                  |
| `encrypted_key`        | ICP → backend → frontend | no (but ciphertext) | Not yet a usable key. Decrypt and verify on the frontend with `TransportSecretKey`.                                                                      |
| `public_key`           | ICP → backend → frontend |       no | Public key used to verify that `encrypted_key` is the correct vetKey.                                                                                  |
| `vetKey`               |                    frontend only |      yes | Root key from which to derive AES keys, etc. Do not send to the backend.                                                                                            |

What matters is that the backend canister **never sees plaintext or the vetKey itself**. The frontend generates a temporary transport key pair, sends only the public key to the canister, and decrypts the returned `encrypted_key` on the frontend. Official docs describe this flow: the transport public key yields an encrypted vetKey that only the frontend can decrypt. ([internetcomputer.org][2])

---

## 2. Backend: Motoko

### `mops.toml`

```toml
[dependencies]
base = "0.16.0"
ic-vetkeys = "0.1.0"
```

Pin versions to match your project’s Motoko / mops setup.

### `src/backend/Main.mo`

```motoko
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import ManagementCanister "mo:ic-vetkeys/ManagementCanister";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

actor class Backend() {

  // Domain separator for this dapp / use case.
  // Must be app-specific so keys do not collide across purposes.
  let DOMAIN_SEPARATOR : [Nat8] =
    Blob.toArray(Text.encodeUtf8("my-private-notes-v1"));

  // Example: store one encrypted note per user.
  // Only ciphertext goes here. Never store plaintext.
  let encryptedNotes =
    HashMap.HashMap<Principal, Blob>(10, Principal.equal, Principal.hash);

  // local dfx: "dfx_test_key".
  // mainnet test: "test_key_1".
  // production: "key_1".
  private func keyId() : ManagementCanister.VetKdKeyid {
    {
      curve = #bls12_381_g2;
      name = "dfx_test_key";
    }
  };

  // In this example, caller principal is part of context.
  // So the same input yields a different vetKey per user.
  private func context(caller : Principal) : Blob {
    let callerBytes = Blob.toArray(Principal.toBlob(caller));

    // [domain length] || domain || caller principal bytes
    // Include domain length to avoid ambiguity from naive concatenation.
    let flattened = Array.flatten<Nat8>([
      [Nat8.fromNat(DOMAIN_SEPARATOR.size())],
      DOMAIN_SEPARATOR,
      callerBytes,
    ]);

    Blob.fromArray(flattened);
  };

  // Receives transport public key and input from the frontend.
  // Return value is the encrypted vetKey—not an AES key yet.
  public shared ({ caller }) func vetkd_derive_key(
    transportKey : Blob,
    input : Blob,
  ) : async Blob {
    await ManagementCanister.vetKdDeriveKey(
      input,
      context(caller),
      keyId(),
      transportKey,
    )
  };

  // Public key for the frontend to verify the encrypted vetKey.
  // Must use the same context / key_id as derive_key.
  public shared ({ caller }) func vetkd_public_key() : async Blob {
    await ManagementCanister.vetKdPublicKey(
      null,
      context(caller),
      keyId(),
    )
  };

  // Store encrypted data.
  public shared ({ caller }) func put_encrypted_note(ciphertext : Blob) : async () {
    encryptedNotes.put(caller, ciphertext);
  };

  // Fetch encrypted data.
  public shared query ({ caller }) func get_encrypted_note() : async ?Blob {
    encryptedNotes.get(caller)
  };
}
```

This `context(caller)` is the core of access control. It is important **not** to accept `context` from the frontend. Using the caller’s principal as authenticated information from the backend avoids design mistakes such as “Alice derives Bob’s key.” Official docs explain that putting the caller identity in `context` makes the vetKey specific to that caller and `input`, so only that caller can obtain and decrypt it. ([internetcomputer.org][2])

---

## 3. Candid interface

Conceptually:

```did
service : {
  vetkd_derive_key : (blob, blob) -> (blob);
  vetkd_public_key : () -> (blob);

  put_encrypted_note : (blob) -> ();
  get_encrypted_note : () -> (opt blob) query;
}
```

On the TypeScript side, `blob` is usually represented as `Uint8Array` or `number[]`. The frontend code below normalizes to `Uint8Array`.

---

## 4. Frontend: TypeScript + `@icp-sdk`

### install

```bash
npm install @icp-sdk/core @icp-sdk/auth @dfinity/vetkeys
```

`@icp-sdk/auth` can be used for Internet Identity authentication. The official quick start imports `AuthClient` from `@icp-sdk/auth/client` and `HttpAgent` from `@icp-sdk/core/agent`. ([ICP JS SDK Docs][3])

### `vetkeyClient.ts`

```ts
import { Actor, HttpAgent } from "@icp-sdk/core/agent";
import { Principal } from "@icp-sdk/core/principal";
import { IDL } from "@icp-sdk/core/candid";
import { AuthClient } from "@icp-sdk/auth/client";

import {
  DerivedPublicKey,
  EncryptedVetKey,
  TransportSecretKey,
  VetKey,
} from "@dfinity/vetkeys";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

type BackendActor = {
  vetkd_derive_key: (
    transportKey: Uint8Array,
    input: Uint8Array,
  ) => Promise<Uint8Array | number[]>;

  vetkd_public_key: () => Promise<Uint8Array | number[]>;

  put_encrypted_note: (ciphertext: Uint8Array) => Promise<void>;

  get_encrypted_note: () => Promise<[] | [Uint8Array | number[]]>;
};

const idlFactory = ({ IDL }: { IDL: typeof import("@icp-sdk/core/candid").IDL }) =>
  IDL.Service({
    vetkd_derive_key: IDL.Func(
      [IDL.Vec(IDL.Nat8), IDL.Vec(IDL.Nat8)],
      [IDL.Vec(IDL.Nat8)],
      [],
    ),
    vetkd_public_key: IDL.Func(
      [],
      [IDL.Vec(IDL.Nat8)],
      [],
    ),
    put_encrypted_note: IDL.Func(
      [IDL.Vec(IDL.Nat8)],
      [],
      [],
    ),
    get_encrypted_note: IDL.Func(
      [],
      [IDL.Opt(IDL.Vec(IDL.Nat8))],
      ["query"],
    ),
  });

function asUint8Array(value: Uint8Array | number[]): Uint8Array {
  return value instanceof Uint8Array ? value : Uint8Array.from(value);
}

function concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

export async function createBackendActor(params: {
  backendCanisterId: string;
  network: "local" | "ic";
}): Promise<BackendActor> {
  const authClient = new AuthClient({
    identityProvider:
      params.network === "ic"
        ? "https://id.ai/authorize"
        : "http://id.ai.localhost:8000",
  });

  if (!authClient.isAuthenticated()) {
    await authClient.signIn();
  }

  const identity = await authClient.getIdentity();

  const agent = await HttpAgent.create({
    identity,
    host:
      params.network === "ic"
        ? "https://icp-api.io"
        : "http://127.0.0.1:4943",
  });

  // Fetch root key on local replica.
  // Not needed on mainnet—do not call unconditionally on mainnet.
  if (params.network === "local") {
    await agent.fetchRootKey();
  }

  return Actor.createActor<BackendActor>(idlFactory, {
    agent,
    canisterId: Principal.fromText(params.backendCanisterId),
  });
}
```

---

## 5. Obtaining a vetKey and turning it into an AES key

The flow has four steps:

1. The frontend creates a temporary transport secret key with `TransportSecretKey.random()`.
2. Send `transportSecretKey.publicKeyBytes()` and `input` to the backend.
3. The backend calls the management canister’s `vetkd_derive_key` and returns `encrypted_key`.
4. The frontend fetches `vetkd_public_key` and recovers the vetKey with `encrypted_key.decryptAndVerify(...)`.

The official TypeScript example follows this order: `TransportSecretKey.random()`, `transportSecretKey.publicKeyBytes()`, `vetkd_derive_key(...)`, `DerivedPublicKey.deserialize(...)`, `decryptAndVerify(...)`. ([internetcomputer.org][2])

```ts
export async function getVetKey(
  backend: BackendActor,
  inputLabel: string,
): Promise<VetKey> {
  // input is a byte string naming which key you want.
  // Examples: "note/default", "note/123", "file:<uuid>"
  const input = textEncoder.encode(inputLabel);

  // Ephemeral secret kept only inside the frontend.
  const transportSecretKey = TransportSecretKey.random();

  // Only the transport public key goes to the backend.
  const encryptedVetKeyBytesRaw = await backend.vetkd_derive_key(
    transportSecretKey.publicKeyBytes(),
    input,
  );

  const encryptedVetKeyBytes = asUint8Array(encryptedVetKeyBytesRaw);
  const encryptedVetKey = new EncryptedVetKey(encryptedVetKeyBytes);

  // Public key for the same context / key_id as derive_key.
  const publicKeyBytesRaw = await backend.vetkd_public_key();
  const publicKey = DerivedPublicKey.deserialize(asUint8Array(publicKeyBytesRaw));

  // Decrypt the encrypted vetKey and verify it matches the intended input.
  const vetKey = encryptedVetKey.decryptAndVerify(
    transportSecretKey,
    publicKey,
    input,
  );

  return vetKey;
}

export async function aesKeyFromVetKey(vetKey: VetKey): Promise<CryptoKey> {
  // 32 bytes for AES-256.
  // domain separator separates “what kind of key derived from this vetKey”.
  const rawAesKey = vetKey.deriveSymmetricKey(
    "my-private-notes-v1/aes-gcm",
    32,
  );

  return crypto.subtle.importKey(
    "raw",
    rawAesKey,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}
```

`VetKey.deriveSymmetricKey(domainSep, outputLength)` derives a symmetric key of the given length from the vetKey. Official Typedoc notes that `domainSep` should be unique and include app name and purpose. ([Dfinity Vetkeys][4])

---

## 6. Encrypting and storing on the canister

```ts
export async function saveEncryptedNote(
  backend: BackendActor,
  plaintext: string,
): Promise<void> {
  // Same inputLabel lets the same user recover the same vetKey later.
  // context includes caller principal, so other users get different keys.
  const vetKey = await getVetKey(backend, "note/default");
  const aesKey = await aesKeyFromVetKey(vetKey);

  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintextBytes = textEncoder.encode(plaintext);

  const ciphertextBuffer = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
    },
    aesKey,
    plaintextBytes,
  );

  const ciphertext = new Uint8Array(ciphertextBuffer);

  // IV is needed for decryption, so store IV || ciphertext.
  const payload = concatBytes(iv, ciphertext);

  await backend.put_encrypted_note(payload);
}
```

At this point the canister only stores `payload = iv || ciphertext`. Because the canister never knows the AES key or plaintext, reading state does not reveal note contents. EncryptedMaps documentation similarly stresses encrypting and decrypting on the frontend while the canister only sees data encrypted under keys it does not know. ([ICP Developer Docs][5])

---

## 7. Loading and decrypting

```ts
export async function loadEncryptedNote(
  backend: BackendActor,
): Promise<string | null> {
  const maybePayload = await backend.get_encrypted_note();

  if (maybePayload.length === 0) {
    return null;
  }

  const payload = asUint8Array(maybePayload[0]);

  const iv = payload.slice(0, 12);
  const ciphertext = payload.slice(12);

  const vetKey = await getVetKey(backend, "note/default");
  const aesKey = await aesKeyFromVetKey(vetKey);

  const plaintextBuffer = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv,
    },
    aesKey,
    ciphertext,
  );

  return textDecoder.decode(plaintextBuffer);
}
```

You must use the same `inputLabel = "note/default"` here. Even a one-byte difference in `input` yields a different vetKey.

---

## 8. What to send, what you get back, and how to use it

### When encrypting and saving

```ts
await saveEncryptedNote(backend, "secret memo");
```

Internally the values passed are:

```ts
input = utf8("note/default")
transport_public_key = transportSecretKey.publicKeyBytes()
```

The backend forwards them to the management canister as:

```motoko
ManagementCanister.vetKdDeriveKey(
  input,
  context(caller),
  keyId(),
  transportKey,
)
```

The return value is `encryptedVetKeyBytes`. It is **not** an AES key yet.

The frontend also receives `publicKeyBytes` from `vetkd_public_key()` and obtains the vetKey with:

```ts
vetKey = encryptedVetKey.decryptAndVerify(
  transportSecretKey,
  publicKey,
  input,
)
```

Then it derives a 32-byte AES-256 key with:

```ts
rawAesKey = vetKey.deriveSymmetricKey("my-private-notes-v1/aes-gcm", 32)
```

and encrypts plaintext with WebCrypto `AES-GCM`. What you store is `iv || ciphertext`.

### When decrypting

You receive `iv || ciphertext` from the canister. Derive the vetKey again with the same `input = utf8("note/default")`. Because the vetKey is deterministic, the same caller, context, and input reproduce the same key. ([internetcomputer.org][2])

Derive the AES key from that vetKey with the same `domainSep`, then decrypt the ciphertext.

---

## 9. Practical `input` design

`input` is a **key name**, not a secret.

```ts
// One secret memo per user
input = "note/default"

// Separate key per note
input = `note/${noteId}`

// Separate key per file
input = `file/${fileId}`

// Separate by purpose
input = `profile/private-fields`
input = `backup/export-key`
```

In this example `context` includes the caller principal, so Alice’s `"note/default"` and Bob’s `"note/default"` are different keys.

```text
Alice:
  context = domain || Alice principal
  input   = "note/default"

Bob:
  context = domain || Bob principal
  input   = "note/default"

=> different vetKeys
```

---

## 10. When you want shared data

The implementation above targets **private data** only the owner can decrypt.

If you need sharing but only use `context(caller)`, others cannot obtain the same key. For sharing, use one of the following:

1. **KeyManager / EncryptedMaps**  
   Official `@dfinity/vetkeys/key_manager` and `@dfinity/vetkeys/encrypted_maps` bundle access control, sharing, and vetKey retrieval behind higher-level APIs. EncryptedMaps identifies an encrypted map by map owner principal and map name; values in the map are transparently encrypted and decrypted on the frontend. ([ICP Developer Docs][5])

2. **Roll your own ACL**  
   Set `context` to `domain || owner || resourceId` and have the backend check that the caller may access `resourceId` before calling `vetKdDeriveKey`.  
   In this case you do not put `caller` directly in context; you use a per-resource context.

---

## 11. Implementation notes

* Do not let the frontend choose `context`. The backend must build it from the authenticated `caller` and ACL.
* `input` is not secret. Design it as a stable, unique key identifier.
* `transportSecretKey` is ephemeral. Usually do not persist it.
* Do not use `encrypted_key` as an AES key. Always run `decryptAndVerify` to obtain the vetKey.
* Do not use `vetKey.signatureBytes()` directly as a cipher key; use `deriveSymmetricKey(...)` for purpose separation.
* Do not store plaintext on the canister. Canister state on a public blockchain is not a secret store.
* Use `dfx_test_key` locally, `test_key_1` for mainnet testing, and `key_1` in production. Supported key names are listed in the official docs. ([internetcomputer.org][2])
* `vetkd_derive_key` calls the management canister and therefore costs cycles. Official docs give per-key cost examples. ([internetcomputer.org][2])

With this setup, the frontend makes authenticated calls to the backend canister via `@icp-sdk`, the backend invokes the vetKD management API from Motoko, and the actual secret key material is decrypted and used only inside the browser on the frontend.

[1]: https://js.icp.build/core/v4.0/installation/ "Installation | ICP JS SDK Docs"
[2]: https://internetcomputer.org/docs/building-apps/network-features/vetkeys/api "vetKD API | Internet Computer"
[3]: https://js.icp.build/auth/latest/quick-start "Quick Start | ICP JS SDK Docs"
[4]: https://5lfyp-mqaaa-aaaag-aleqa-cai.icp0.io/classes/_dfinity_vetkeys.VetKey.html?utm_source=chatgpt.com "VetKey | @dfinity/vetkeys - v0.1.0"
[5]: https://docs.internetcomputer.org/building-apps/network-features/vetkeys/encrypted-onchain-storage "Encrypted onchain storage | Internet Computer"
