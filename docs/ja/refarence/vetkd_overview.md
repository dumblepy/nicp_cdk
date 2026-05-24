以下は「低レベル vetKD API を直接使い、ユーザーごとの AES-GCM 鍵をブラウザで得る」実装例です。ICP との通信・認証は `@icp-sdk`、vetKey の復号・検証・鍵導出は公式の `@dfinity/vetkeys` を使います。ICP JS SDK では `@icp-sdk/core` が IC との通信用パッケージで、actor 作成には `@icp-sdk/core/agent` を使います。([ICP JS SDK Docs][1]) vetKey 用ユーティリティは現行公式例でも `@dfinity/vetkeys` から `DerivedPublicKey`, `TransportSecretKey`, `EncryptedVetKey` を import しています。([internetcomputer.org][2])

## 1. vetKey の基本構造

vetKey は、ICP の subnet が持つ threshold master key から、次の値で決定論的に導出される鍵です。同じ `key_id + canister_id + context + input` なら同じ vetKey になります。公式 API でも「同じ入力は同じ鍵を返し、異なる input で無制限に別鍵を作れる」と説明されています。([internetcomputer.org][2])

管理 canister の実体 API はこの 2 つです。

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

各値の意味はこうです。

| 値                      |                     誰が作る |          秘密か | 役割                                                                                                                        |
| ---------------------- | -----------------------: | -----------: | ------------------------------------------------------------------------------------------------------------------------- |
| `key_id`               |                  backend |          いいえ | どの master key を使うか。例: local は `dfx_test_key`、mainnet test は `test_key_1`、production は `key_1`。([internetcomputer.org][2]) |
| `context`              |                  backend |          いいえ | dapp・用途・ユーザー・権限範囲を分離するドメイン。例では `domain separator + caller principal`。                                                     |
| `input`                |     frontend または backend |          いいえ | 個別鍵の識別子。例: `"note/default"`、`"file:<uuid>"`。同じ context 内で input を変えると別鍵。                                                  |
| `transport_public_key` |                 frontend |          いいえ | 返却される vetKey をフロントエンドだけが復号できるようにする一時公開鍵。                                                                                  |
| `encrypted_key`        | ICP → backend → frontend | いいえ、ただし暗号化済み | まだ使える鍵ではない。frontend の `TransportSecretKey` で復号・検証する。                                                                      |
| `public_key`           | ICP → backend → frontend |          いいえ | `encrypted_key` が正しい vetKey か検証するための公開鍵。                                                                                  |
| `vetKey`               |           frontend だけが得る |           はい | AES 鍵などを導出する元鍵。backend には渡さない。                                                                                            |

暗号化・復号の実装でよく出てくる変数、値、鍵を日本語名付きで整理するとこうなります。`*_hex` / `*Hex` は、同じ bytes を画面表示やコピー用に 16 進文字列へ変換したものです。

| 公式 API / TypeScript 名 | 日本語名 | 型・表現 | 誰が作る / 持つ | 秘密か | 暗号化時の使い方 | 復号時の使い方 |
| --- | --- | --- | --- | --- | --- | --- |
| `key_id` | master key ID / しきい値 master key の識別子 | `{ curve; name }` | backend | いいえ | management canister に渡し、どの subnet の master key から vetKey を導出するか決める。 | 暗号化時と同じ `key_id` を使う。違う `key_id` では別の vetKey になる。 |
| `context` | 文脈 / 用途分離ラベル | `blob` | backend | いいえ | dapp、用途、caller principal、ACL などを混ぜ、鍵の利用範囲を分離する。 | 暗号化時と同じ `context` を backend が再構成する。 |
| `input` | 鍵入力 / 個別鍵名 | `Uint8Array` / `blob` | frontend または backend | いいえ | `"note/default"` や resource ID など、欲しい vetKey を識別する。 | 暗号化時と同じ `input` を `decryptAndVerify(...)` に渡す。1 byte でも違うと別鍵になる。 |
| `transportSecretKey` | 配送秘密鍵 | `TransportSecretKey` | frontend | はい | `TransportSecretKey.random()` で生成し、frontend 内だけに置く。 | `encryptedVetKey.decryptAndVerify(transportSecretKey, publicKey, input)` で encrypted vetKey を復号する。通常は保存しない。 |
| `transportSecretKeyHex` | 配送秘密鍵 hex | `text` | frontend | はい | デバッグ UI や手動復号 UI で一時秘密鍵を表示・再入力するための表現。 | 復号 UI から読み、`TransportSecretKey.deserialize(...)` などで bytes / key に戻す。公開・ログ出力しない。 |
| `transportSecretKey.publicKeyBytes()` / `transport_public_key` | 配送公開鍵 | `Uint8Array` / `blob` | frontend | いいえ | backend に渡す。management canister はこの公開鍵宛に vetKey を暗号化して返す。 | 直接は使わない。対応する `transportSecretKey` が encrypted vetKey の復号に必要。 |
| `transportPublicKeyHex` | 配送公開鍵 hex | `text` | frontend | いいえ | `transport_public_key` を backend API に渡すため、またはログ・UI 表示用に hex 化したもの。 | 通常は使わない。再 derive する場合は改めて新しい transport key pair を作る。 |
| `encrypted_key` / `encryptedVetKeyBytes` | 暗号化済み vetKey | `Uint8Array` / `blob` | management canister | いいえ、ただし暗号化済み | `vetkd_derive_key` の戻り値。まだ AES 鍵でも平文の vetKey でもない。 | `new EncryptedVetKey(encryptedVetKeyBytes)` で包み、`decryptAndVerify(...)` へ渡す。 |
| `encrypted_key_hex` / `encryptedVetKeyHex` | 暗号化済み vetKey hex | `text` | backend → frontend | いいえ、ただし暗号化済み | backend が bytes を hex 文字列で返す実装では、frontend がこれを受け取る。 | 復号 UI から読み、bytes に戻して encrypted vetKey として扱う。 |
| `public_key` / `publicKeyBytes` | vetKD 公開鍵 / 導出公開鍵 | `Uint8Array` / `blob` | management canister | いいえ | 暗号化処理そのものには不要だが、encrypted vetKey を検証可能にするため取得する。 | `DerivedPublicKey.deserialize(publicKeyBytes)` で復元し、`decryptAndVerify(...)` で検証に使う。 |
| `publicKey` | 導出公開鍵オブジェクト | `DerivedPublicKey` | frontend | いいえ | `publicKeyBytes` から復元する。 | encrypted vetKey が同じ `input` / `context` / `key_id` に対応することを検証する。 |
| `vetKey` | vetKey / 検証済み派生秘密鍵 | `VetKey` | frontend | はい | `deriveSymmetricKey(...)` や `asDerivedKeyMaterial()` で暗号化用の鍵素材を作る。backend に送らない。 | 同じ手順で再取得し、同じ用途分離ラベルで復号用の鍵素材を作る。 |
| `domainSep` / `domain separator` | 用途分離ラベル | `string` / bytes | frontend または backend | いいえ | vetKey から「この用途専用」の対称鍵・鍵素材を導出する。例: `"my-private-notes-v1/aes-gcm"`。 | 暗号化時と同じ値を使う。違う値では復号できない。 |
| `rawAesKey` / `aesKey` | AES 鍵 / 対称暗号鍵 | `Uint8Array` / `CryptoKey` | frontend | はい | WebCrypto の `AES-GCM` で平文を暗号化する。 | WebCrypto の `AES-GCM` で ciphertext を復号する。backend に渡さない。 |
| `iv` | 初期化ベクトル / nonce | `Uint8Array` | frontend | いいえ | 暗号化ごとにランダム生成し、AES-GCM に渡す。 | 復号に必須。ciphertext と一緒に保存・取得する。 |
| `plaintext` / `plaintextBytes` | 平文 / 平文 bytes | `string` / `Uint8Array` | frontend / ユーザー | はい | 暗号化前のデータ。canister に送らない。 | 復号結果として frontend だけで得る。 |
| `ciphertext` / `ciphertextBytes` | 暗号文 | `Uint8Array` / `blob` | frontend | いいえ、ただし秘匿対象 | canister に保存するデータ。 | canister から取得し、AES 鍵または vetKey 由来の鍵素材で復号する。 |
| `ciphertextHex` | 暗号文 hex | `text` | frontend / backend | いいえ、ただし秘匿対象 | デバッグ UI や保存確認用に暗号文を hex 表示したもの。 | 復号 UI から読み、bytes に戻して復号する。 |
| `payload = iv || ciphertext` | 保存ペイロード | `Uint8Array` / `blob` | frontend | いいえ、ただし秘匿対象 | 復号に必要な `iv` と暗号文を連結して canister に保存する。 | 先頭 12 bytes を `iv`、残りを `ciphertext` として分ける。 |

この表のうち、本当に secret として扱う必要があるのは `transportSecretKey`、`transportSecretKeyHex`、`vetKey`、`rawAesKey` / `aesKey`、`plaintext` です。`encrypted_key` / `encryptedVetKeyBytes` と `ciphertext` は暗号化済みなので平文ではありませんが、不要に公開すると攻撃面やメタデータ漏洩が増えるため、公開値として雑に扱わない方が安全です。

重要なのは、backend canister は **平文データも vetKey 本体も見ない** ことです。frontend が一時 transport key pair を作り、その公開鍵だけを canister に渡し、返ってきた `encrypted_key` を frontend 側で復号します。公式 docs でも、この transport public key により「frontend だけが復号できる encrypted vetKey」を取得する流れになっています。([internetcomputer.org][2])

---

## 2. Backend: Motoko

### `mops.toml`

```toml
[dependencies]
base = "0.16.0"
ic-vetkeys = "0.1.0"
```

バージョンはプロジェクトの Motoko / mops 環境に合わせて固定してください。

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

  // この dapp / 用途専用の domain separator。
  // 別用途の鍵と衝突させないために、必ずアプリ固有の値にする。
  let DOMAIN_SEPARATOR : [Nat8] =
    Blob.toArray(Text.encodeUtf8("my-private-notes-v1"));

  // 例として、ユーザーごとに暗号化済み note を 1 つ保存する。
  // ここに入るのは ciphertext だけ。平文は絶対に入れない。
  let encryptedNotes =
    HashMap.HashMap<Principal, Blob>(10, Principal.equal, Principal.hash);

  // local dfx なら "dfx_test_key"。
  // mainnet test なら "test_key_1"。
  // 本番なら "key_1"。
  private func keyId() : ManagementCanister.VetKdKeyid {
    {
      curve = #bls12_381_g2;
      name = "dfx_test_key";
    }
  };

  // この例では caller principal を context に入れる。
  // つまり、同じ input でもユーザーごとに別 vetKey になる。
  private func context(caller : Principal) : Blob {
    let callerBytes = Blob.toArray(Principal.toBlob(caller));

    // [domain length] || domain || caller principal bytes
    // 単純連結の曖昧性を避けるため domain length を入れる。
    let flattened = Array.flatten<Nat8>([
      [Nat8.fromNat(DOMAIN_SEPARATOR.size())],
      DOMAIN_SEPARATOR,
      callerBytes,
    ]);

    Blob.fromArray(flattened);
  };

  // frontend が作った transport public key と input を受け取る。
  // 戻り値は「暗号化された vetKey」。まだ AES 鍵ではない。
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

  // frontend が encrypted vetKey を検証するための public key。
  // derive_key と同じ context / key_id を使う必要がある。
  public shared ({ caller }) func vetkd_public_key() : async Blob {
    await ManagementCanister.vetKdPublicKey(
      null,
      context(caller),
      keyId(),
    )
  };

  // 暗号化済みデータを保存。
  public shared ({ caller }) func put_encrypted_note(ciphertext : Blob) : async () {
    encryptedNotes.put(caller, ciphertext);
  };

  // 暗号化済みデータを取得。
  public shared query ({ caller }) func get_encrypted_note() : async ?Blob {
    encryptedNotes.get(caller)
  };
}
```

この `context(caller)` がアクセス制御の中核です。frontend から `context` を受け取らないのが重要です。caller の principal を backend が認証済み情報として使うことで、「Alice が Bob 用の鍵を勝手に取得する」設計ミスを避けます。公式 docs でも、caller identity を `context` に使うことで、その caller と `input` に固有の vetKey になり、その caller だけが取得・復号できると説明されています。([internetcomputer.org][2])

---

## 3. Candid interface

概念的にはこうなります。

```did
service : {
  vetkd_derive_key : (blob, blob) -> (blob);
  vetkd_public_key : () -> (blob);

  put_encrypted_note : (blob) -> ();
  get_encrypted_note : () -> (opt blob) query;
}
```

`blob` は TypeScript 側では通常 `Uint8Array` または `number[]` として扱われます。以下の frontend コードでは `Uint8Array` に正規化します。

---

## 4. Frontend: TypeScript + `@icp-sdk`

### install

```bash
npm install @icp-sdk/core @icp-sdk/auth @dfinity/vetkeys
```

`@icp-sdk/auth` は Internet Identity 認証に使えます。公式 quick start でも `AuthClient` は `@icp-sdk/auth/client`、`HttpAgent` は `@icp-sdk/core/agent` から import されています。([ICP JS SDK Docs][3])

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

  // local replica では root key を取得する。
  // mainnet では不要。mainnet で無条件に呼ばない。
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

## 5. vetKey を取得して AES 鍵にする

流れは 4 段階です。

1. frontend が `TransportSecretKey.random()` で一時 transport secret key を作る。
2. `transportSecretKey.publicKeyBytes()` と `input` を backend に渡す。
3. backend は management canister に `vetkd_derive_key` を呼び、`encrypted_key` を返す。
4. frontend は `vetkd_public_key` を取得し、`encrypted_key.decryptAndVerify(...)` で vetKey に戻す。

公式 TypeScript 例もこの順序です。`TransportSecretKey.random()`、`transportSecretKey.publicKeyBytes()`、`vetkd_derive_key(...)`、`DerivedPublicKey.deserialize(...)`、`decryptAndVerify(...)` を使います。([internetcomputer.org][2])

```ts
export async function getVetKey(
  backend: BackendActor,
  inputLabel: string,
): Promise<VetKey> {
  // input は「どの鍵が欲しいか」を表す byte string。
  // 例: "note/default", "note/123", "file:<uuid>"
  const input = textEncoder.encode(inputLabel);

  // frontend 内だけに保持する一時秘密鍵。
  const transportSecretKey = TransportSecretKey.random();

  // backend に渡すのは transport public key だけ。
  const encryptedVetKeyBytesRaw = await backend.vetkd_derive_key(
    transportSecretKey.publicKeyBytes(),
    input,
  );

  const encryptedVetKeyBytes = asUint8Array(encryptedVetKeyBytesRaw);
  const encryptedVetKey = new EncryptedVetKey(encryptedVetKeyBytes);

  // derive_key と同じ context/key_id に対応する public key。
  const publicKeyBytesRaw = await backend.vetkd_public_key();
  const publicKey = DerivedPublicKey.deserialize(asUint8Array(publicKeyBytesRaw));

  // encrypted vetKey を復号し、正しい input に対するものか検証する。
  const vetKey = encryptedVetKey.decryptAndVerify(
    transportSecretKey,
    publicKey,
    input,
  );

  return vetKey;
}

export async function aesKeyFromVetKey(vetKey: VetKey): Promise<CryptoKey> {
  // 32 bytes = AES-256 用。
  // domain separator は「この vetKey から何用途の鍵を導出するか」を分離する。
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

`VetKey.deriveSymmetricKey(domainSep, outputLength)` は、vetKey から指定長の対称鍵を導出するための API です。`domainSep` はアプリ名と用途を含めた一意の値にする、という注意も公式 Typedoc にあります。([Dfinity Vetkeys][4])

---

## 6. 暗号化して canister に保存する

```ts
export async function saveEncryptedNote(
  backend: BackendActor,
  plaintext: string,
): Promise<void> {
  // この inputLabel が同じなら、同じユーザーは同じ vetKey を再取得できる。
  // context に caller principal が入っているので、別ユーザーは別鍵になる。
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

  // 復号時に IV が必要なので、IV || ciphertext として保存する。
  const payload = concatBytes(iv, ciphertext);

  await backend.put_encrypted_note(payload);
}
```

この時点で canister に保存されるのは `payload = iv || ciphertext` だけです。canister は AES 鍵も平文も知らないため、状態が読まれても note の中身は見えません。EncryptedMaps の公式説明でも、暗号化・復号は frontend で行い、canister は自分が知らない鍵で暗号化されたデータだけを見る、という設計が強調されています。([ICP Developer Docs][5])

---

## 7. 取得して復号する

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

ここで同じ `inputLabel = "note/default"` を使う必要があります。`input` が 1 byte でも違うと別 vetKey になります。

---

## 8. 何を渡し、何を受け取り、どう使うか

### 暗号化・保存時

```ts
await saveEncryptedNote(backend, "secret memo");
```

内部で渡している値はこうです。

```ts
input = utf8("note/default")
transport_public_key = transportSecretKey.publicKeyBytes()
```

backend はこれを受け取り、management canister にこう渡します。

```motoko
ManagementCanister.vetKdDeriveKey(
  input,
  context(caller),
  keyId(),
  transportKey,
)
```

返る値は `encryptedVetKeyBytes` です。これはまだ AES 鍵ではありません。

frontend はさらに `vetkd_public_key()` から `publicKeyBytes` を受け取り、

```ts
vetKey = encryptedVetKey.decryptAndVerify(
  transportSecretKey,
  publicKey,
  input,
)
```

で vetKey を得ます。その後、

```ts
rawAesKey = vetKey.deriveSymmetricKey("my-private-notes-v1/aes-gcm", 32)
```

で 32 byte の AES-256 鍵を導出し、WebCrypto の `AES-GCM` で平文を暗号化します。保存するのは `iv || ciphertext` です。

### 復号時

canister から `iv || ciphertext` を受け取ります。もう一度、同じ `input = utf8("note/default")` で vetKey を取得します。vetKey は deterministic なので、同じ caller・同じ context・同じ input なら同じ鍵を再取得できます。([internetcomputer.org][2])

その vetKey から同じ `domainSep` で AES key を導出し、ciphertext を復号します。

---

## 9. `input` 設計の実例

`input` は「鍵の名前」です。秘密値ではありません。

```ts
// ユーザーごとに 1 つの秘密メモ
input = "note/default"

// note ごとに別鍵
input = `note/${noteId}`

// ファイルごとに別鍵
input = `file/${fileId}`

// 用途ごとに分離
input = `profile/private-fields`
input = `backup/export-key`
```

この例では `context` に caller principal が入るため、Alice の `"note/default"` と Bob の `"note/default"` は別鍵です。

```text
Alice:
  context = domain || Alice principal
  input   = "note/default"

Bob:
  context = domain || Bob principal
  input   = "note/default"

=> 別 vetKey
```

---

## 10. 共有データを作りたい場合

上の実装は「本人だけが復号できる private data」用です。

共有したい場合に `context(caller)` だけを使うと、他人が同じ鍵を取得できません。共有には次のどちらかを使います。

1. **KeyManager / EncryptedMaps を使う**
   公式 `@dfinity/vetkeys/key_manager` と `@dfinity/vetkeys/encrypted_maps` は、アクセス権管理・共有・vetKey 取得を高レベル API にまとめています。EncryptedMaps は map owner principal と map name で encrypted map を識別し、map 内の値は frontend 側で透過的に暗号化・復号される設計です。([ICP Developer Docs][5])

2. **自前で ACL を作る**
   `context` を `domain || owner || resourceId` にし、backend 側で「caller がその resourceId にアクセス可能か」を検査してから `vetKdDeriveKey` を呼びます。
   この場合、`caller` を context に直接入れるのではなく、resource 単位の context にします。

---

## 11. 実装上の注意点

* `context` は frontend に決めさせない。backend が認証済み `caller` と ACL から組み立てる。
* `input` は秘密ではない。鍵識別子として安定・一意に設計する。
* `transportSecretKey` は一時鍵。通常は保存しない。
* `encrypted_key` を AES 鍵として使わない。必ず `decryptAndVerify` して vetKey を得る。
* `vetKey.signatureBytes()` を直接暗号鍵として使わず、`deriveSymmetricKey(...)` で用途分離した鍵を作る。
* canister には平文を保存しない。public blockchain 上の canister state は秘密ストレージではない。
* local は `dfx_test_key`、mainnet の検証は `test_key_1`、本番は `key_1` に切り替える。サポートされる key name は公式 docs に列挙されています。([internetcomputer.org][2])
* `vetkd_derive_key` は management canister 呼び出しなので cycles cost がある。公式 docs は key ごとの費用例を掲載しています。([internetcomputer.org][2])

この構成なら、frontend は `@icp-sdk` で backend canister に認証済み call を行い、backend は Motoko で vetKD management API を呼び、実際の秘密鍵 material は frontend のブラウザ内だけで復号・利用されます。

[1]: https://js.icp.build/core/v4.0/installation/ "Installation | ICP JS SDK Docs"
[2]: https://internetcomputer.org/docs/building-apps/network-features/vetkeys/api "vetKD API | Internet Computer"
[3]: https://js.icp.build/auth/latest/quick-start "Quick Start | ICP JS SDK Docs"
[4]: https://5lfyp-mqaaa-aaaag-aleqa-cai.icp0.io/classes/_dfinity_vetkeys.VetKey.html?utm_source=chatgpt.com "VetKey | @dfinity/vetkeys - v0.1.0"
[5]: https://docs.internetcomputer.org/building-apps/network-features/vetkeys/encrypted-onchain-storage "Encrypted onchain storage | Internet Computer"
