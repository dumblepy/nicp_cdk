vetKey を使った暗号化・復号の概要です。

vetKey は、Internet Computer の management canister から取得する **暗号化済みの鍵素材** を、クライアント側で transport secret key によって復元し、その鍵素材から用途ごとの対称鍵を導出して暗号化・復号に使う仕組みです。

この文書では、特定の画面やサンプル実装の手順ではなく、vetKey を使うときにどの値を生成し、どの値を canister に渡し、どの値を復号時に再利用する必要があるかを整理します。

## 1. 基本の流れ

### 暗号化前に行うこと

1. クライアントで transport key pair を生成する
2. transport public key を canister に渡す
3. canister が management canister の `vetkd_public_key` と `vetkd_derive_key` を呼び出す
4. canister から derived public key と encrypted vetKey を受け取る
5. クライアントで encrypted vetKey を復号し、vetKey 由来の鍵素材を得る

### 暗号化

1. vetKey 由来の鍵素材から、用途ごとの `domainSep` で暗号化用の対称鍵を導出する
2. 平文 bytes を暗号化して ciphertext bytes を得る
3. 後で復号するために、ciphertext と復号に必要な値を保持する

### 復号

1. 暗号化時と同じ encrypted vetKey、transport secret key、ciphertext、domainSep を用意する
2. encrypted vetKey を transport secret key で復元し、同じ鍵素材を得る
3. 暗号化時と同じ `domainSep` で復号用の対称鍵を導出する
4. ciphertext bytes を復号して平文 bytes を得る

## 2. 暗号化・復号で扱う値

`*_hex` は bytes を 16 進文字列にした表現です。実装では bytes のまま扱ってもかまいませんが、UI 入力欄、Candid の `text`、ログ、JSON などに出す場合は hex 表現にすると扱いやすくなります。


| 値                                           | 日本語名          | 生成・取得元                                          | 主な利用箇所                                            | 復号時に必要か                         | 秘密情報か | 保存・共有の考え方                                                       |
| ------------------------------------------- | ------------- | ----------------------------------------------- | ------------------------------------------------- | ------------------------------- | ----- | --------------------------------------------------------------- |
| `transportSecretKey` / `transportSecretHex` | transport 秘密鍵 | クライアントが一時生成する                                   | encrypted vetKey の復元                              | はい                              | はい    | クライアントだけで保持する。漏れると encrypted vetKey を復元できるため、サーバーやログへ出さない       |
| `transportPublicKey` / `transportPublicHex` | transport 公開鍵 | transport 秘密鍵から計算する                             | `vetkd_derive_key` に渡す                            | いいえ                             | いいえ   | canister に送信してよい。復号時は通常不要                                       |
| `keyId`                                     | vetKD 鍵 ID    | canister 側の設定                                   | `vetkd_public_key` / `vetkd_derive_key` の対象鍵を指定する | 条件確認には有用                        | いいえ   | アプリの設定として固定することが多い。例: `key_1`                                   |
| `context` / `context_label`                 | 導出コンテキスト      | アプリが用途に応じて決める                                   | derived public key と encrypted vetKey の導出範囲を分離する  | 同じ encrypted vetKey を再取得する場合に必要 | いいえ   | アプリ、ユーザー、用途ごとに衝突しない値にする                                         |
| `input` / `input_label`                     | 導出入力          | アプリが用途に応じて決める                                   | 個別の vetKey を導出する                                  | 同じ encrypted vetKey を再取得する場合に必要 | 通常いいえ | ユーザー ID、データ種別、バージョンなどを含め、復元可能な形で設計する                            |
| `keyVersion`                                | 鍵バージョン        | アプリが決める                                         | `input` の一部、または鍵ローテーション条件として使う                    | 直接の復号には不要なことが多い                 | いいえ   | どの条件で暗号化したかを確認できるよう ciphertext のメタデータとして残す                      |
| `derivedPublicKey` / `public_key_hex`       | 導出公開鍵         | `vetkd_public_key` の戻り値                         | encrypted vetKey の検証、公開鍵ベースの処理                    | ライブラリの検証方式によって必要                | いいえ   | 公開してよい。encrypted vetKey を検証する設計では ciphertext のメタデータとして残す        |
| `encryptedVetKey`                           | 暗号化済み vetKey  | `vetkd_derive_key` の戻り値                         | クライアントで vetKey を復元する                              | はい                              | 暗号化済み | transport secret key がなければ復元できないが、ciphertext と一緒に扱う重要な材料として保管する |
| `vetKey`                                    | 復元済み vetKey   | encrypted vetKey を transport secret key で復号して得る | 対称鍵や鍵素材の導出                                        | 中間値として必要                        | はい    | 永続保存せず、必要時にメモリ上で扱う                                              |
| `derivedKeyMaterial`                        | vetKey 由来の鍵素材 | `vetKey.asDerivedKeyMaterial()` などで得る           | `encryptMessage` / `decryptMessage`、または対称鍵導出      | 中間値として必要                        | はい    | エクスポートやログ出力を避け、メモリ上で短時間だけ扱う                                     |
| `domainSep`                                 | 用途分離ラベル       | アプリが用途ごとに決める                                    | 対称鍵導出、暗号化、復号                                      | はい                              | いいえ   | 暗号化時と復号時で完全に同じ値を使う。用途ごとに一意にする                                   |
| `plaintext`                                 | 平文            | ユーザー入力やアプリデータ                                   | 暗号化対象                                             | 復号結果として得る                       | はい    | 暗号化前後の取り扱いに注意する。canister に保存しない設計が基本                            |
| `ciphertext` / `ciphertextHex`              | 暗号文           | クライアントの暗号化処理                                    | 保存、送信、復号                                          | はい                              | 暗号化済み | canister や外部ストレージに保存してよいが、改ざん検知できる暗号方式を使う                       |


## 3. 復号に最低限そろえる値

暗号文を復号するには、少なくとも次の値が同じ組み合わせで必要です。


| 値                    | 理由                       |
| -------------------- | ------------------------ |
| `transportSecretKey` | encrypted vetKey を復元するため |
| `encryptedVetKey`    | vetKey 由来の鍵素材を得るため       |
| `ciphertext`         | 復号対象の暗号文                 |
| `domainSep`          | 暗号化時と同じ対称鍵を導出するため        |


実装によっては、encrypted vetKey を再取得するために `context`、`input`、`keyVersion`、`keyId`、`transportPublicKey` を再利用します。すでに encrypted vetKey を ciphertext のメタデータとして保存している場合、復号処理そのものではこれらを直接使わないこともあります。

## 4. キャニスター通信なしで復号するためにブラウザへ保存する値

復号時に canister と通信しない設計にする場合、復号に必要な値を暗号化時点でブラウザ側へ保存しておく必要があります。この場合の最小セットは次の 4 つです。


| 値                                           | 保存する理由                    | 形式の例       | 注意点                               |
| ------------------------------------------- | ------------------------- | ---------- | --------------------------------- |
| `transportSecretKey` / `transportSecretHex` | `encryptedVetKey` を復元するため | hex string | 秘密値。ブラウザに保存すると、そのブラウザ環境で復号可能になる   |
| `encryptedVetKey` / `encryptedVetKeyHex`    | vetKey 由来の鍵素材を得るため        | hex string | `vetkd_derive_key` を再実行しないために保存する |
| `ciphertext` / `ciphertextHex`              | 復号対象の暗号文                  | hex string | 暗号文本体。複数件ある場合はレコードごとに保存する         |
| `domainSep`                                 | 暗号化時と同じ対称鍵を導出するため         | string     | 固定値ならコード側の定数でもよいが、将来変更に備えるなら保存する  |


`domainSep` がアプリ内で固定され、将来も変えない前提なら、保存データから省略してコード定数として扱えます。その場合、ブラウザに保存する実データの最小セットは `transportSecretHex`、`encryptedVetKeyHex`、`ciphertextHex` の 3 つです。

ただし、`transportSecretKey` を保存する設計は「このブラウザに復号能力を保存する」ことを意味します。XSS、ブラウザ拡張、端末の共有、ローカルストレージの抜き取りが起きると、保存済みの `encryptedVetKey` と `ciphertext` から平文を復元される可能性があります。安全性を優先するなら、保存前にユーザーのパスフレーズや WebAuthn など、ブラウザ外またはユーザー操作に依存する鍵で保存レコード全体をさらに暗号化します。

### 保存レコードの例

ブラウザには、値を個別に散らばらせず、バージョン付きの 1 レコードとして保存すると扱いやすくなります。

```json
{
  "schema": "vetkey-offline-decrypt-v1",
  "transportSecretHex": "...",
  "encryptedVetKeyHex": "...",
  "ciphertextHex": "...",
  "domainSep": "private-kv-v1",
  "keyVersion": "0",
  "createdAt": "2026-05-25T00:00:00.000Z"
}
```


| フィールド                | 必須か         | 用途                     |
| -------------------- | ----------- | ---------------------- |
| `schema`             | 推奨          | 保存形式を将来変更したときに判別する     |
| `transportSecretHex` | 必須          | encrypted vetKey を復元する |
| `encryptedVetKeyHex` | 必須          | vetKey 由来の鍵素材を得る       |
| `ciphertextHex`      | 必須          | 復号対象                   |
| `domainSep`          | 固定定数でないなら必須 | 暗号化時と同じ対称鍵を導出する        |
| `keyVersion`         | 任意          | 表示、確認、再取得設計へ戻す場合の補助情報  |
| `createdAt`          | 任意          | デバッグ、移行、削除判断に使う        |


### 保存先の選び方


| 保存先                          | 向いている用途                 | 注意点                                        |
| ---------------------------- | ----------------------- | ------------------------------------------ |
| `IndexedDB`                  | 複数レコード、サイズが大きいデータ、将来の拡張 | 実装は少し増えるが、構造化データとして管理しやすい                  |
| `localStorage`               | 小さなデモ、1 件だけの保存、手早い検証    | 同一 origin の JavaScript から同期的に読めるため、XSS に弱い |
| `sessionStorage`             | タブを閉じるまでの一時保存           | ブラウザ再起動後のオフライン復号には使えない                     |
| WebCrypto で暗号化した `IndexedDB` | 秘密値を保存したい本番寄りの設計        | 復号用の別鍵をどこから得るかを設計する必要がある                   |


最小実装なら `localStorage` に上記 JSON を保存できます。本番を意識するなら、`IndexedDB` に保存し、保存レコード全体を WebCrypto で暗号化する構成が扱いやすいです。

### 復号時の流れ

1. ブラウザ保存からレコードを読み込む
2. `schema` を確認する
3. `transportSecretHex`、`encryptedVetKeyHex`、`ciphertextHex` を hex から bytes に戻す
4. 保存済み、またはコード定数の `domainSep` を使う
5. `decryptCiphertextWithVetkey(transportSecretHex, encryptedVetKeyHex, ciphertextBytes, domainSep)` を呼ぶ

この流れでは、`transportPublicKey`、`context`、`input`、`keyId`、`derivedPublicKey` を復号時に使いません。これらは encrypted vetKey を canister から再取得したり、検証 API で厳密に確認したりする設計に戻す場合のメタデータです。

## 5. 保存する値と保存しない値

### 保存してよい値


| 値                                  | 保存先の例                    | 注意点                                               |
| ---------------------------------- | ------------------------ | ------------------------------------------------- |
| `ciphertext`                       | canister、外部 DB、ローカルストレージ | 平文ではないが、削除・改ざん・リプレイへの対策は別途考える                     |
| `encryptedVetKey`                  | ciphertext のメタデータ        | transport secret key と組み合わせると鍵素材を復元できるため、扱いは慎重にする |
| `context` / `input` / `keyVersion` | ciphertext のメタデータ        | 後から同じ vetKey を再取得する設計では必須                         |
| `domainSep`                        | アプリ設定、メタデータ              | 固定値ならコードに持たせてもよい。変更すると既存 ciphertext を復号できなくなる     |
| `derivedPublicKey`                 | メタデータ、キャッシュ              | 検証に使う場合は、どの `context` の公開鍵かを明確にする                 |


キャニスター通信なしの復号を優先する場合に限り、`transportSecretKey` もブラウザへ保存する対象になります。その場合は「保存してよい公開メタデータ」ではなく「ブラウザに預ける秘密値」として扱い、保存レコード全体を追加で暗号化することを検討します。

### 通常は保存・共有しない値


| 値                    | 理由                            |
| -------------------- | ----------------------------- |
| `transportSecretKey` | encrypted vetKey を復元できる秘密鍵のため |
| `vetKey`             | 復元済みの鍵そのもののため                 |
| `derivedKeyMaterial` | 暗号化・復号に使う鍵素材のため               |
| `plaintext`          | 暗号化で保護したい元データのため              |


オフライン復号のために `transportSecretKey` を保存する場合は、この通常ルールの例外です。その場合でも、保存先を「公開メタデータの置き場」ではなく「復号権限そのものを預ける場所」として扱います。

## 6. 実装上の注意

- `context` と `input` は、アプリ、ユーザー、データ種別、バージョンの境界が混ざらないように設計する
- `domainSep` は対称鍵導出の用途分離に使うため、暗号化と復号で同じ値を使い、別用途では別の値にする
- transport secret key は一時鍵として扱い、ログ、URL、canister 引数、永続ストレージに出さない
- キャニスター通信なしの復号をしたい場合だけ、transport secret key をブラウザ保存の秘密値として扱う
- ciphertext を保存する場合は、復号に必要な `encryptedVetKey` や導出条件のメタデータも一緒に管理する
- `keyVersion` は復号関数の直接引数ではなくても、鍵ローテーションや「どの条件で暗号化したか」の確認に役立つ
- ライブラリが `EncryptedVetKey.decryptAndVerify(...)` のような検証 API を提供している場合は、derived public key と input を使って復元した vetKey を検証する

## 7. 関連ファイル

- `examples/vetkey/frontend/app/src/lib/vetkeyCrypto.ts`
- `examples/vetkey/frontend/app/src/components/PrivateKvRoundtrip.tsx`
- `examples/vetkey/backend/src/controller.nim`

