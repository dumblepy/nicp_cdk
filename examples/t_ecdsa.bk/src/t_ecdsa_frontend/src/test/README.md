# Ethereum署名テスト

このディレクトリには、ICPキャニスターのEthereum署名機能をviemライブラリを使用してテストするためのTypeScriptテストが含まれています。

## テストの概要

テストは以下の機能を検証します:

1. **ウォレットアドレスの取得**: `getEvmAddress`関数でEthereum形式のアドレスを取得
2. **メッセージの署名**: `signWithEthereum`関数でメッセージに署名
3. **署名の検証**: viemの`verifyMessage`関数で署名を検証
4. **ICPキャニスター内での検証**: `verifyWithEthereum`関数でキャニスター側でも検証
5. **エラーケース**: 不正なアドレスや改ざんされたメッセージの検証が失敗することを確認

## 事前準備

テストを実行する前に、以下のステップを順番に実行してください。

### 1. 依存関係のインストール

```bash
cd /application/examples/t_ecdsa
pnpm install
```

### 2. ICPローカル環境の起動

```bash
cd /application/examples/t_ecdsa
dfx start --clean --background
```

### 3. バックエンドキャニスターのビルドとデプロイ

```bash
cd /application/examples/t_ecdsa
./build.sh
dfx deploy t_ecdsa_backend
dfx generate
```

この時点で、`src/declarations/t_ecdsa_backend`配下に型定義ファイルが生成され、`.env`ファイルにキャニスターIDが書き込まれます。

## テストの実行

### すべてのテストを実行

```bash
cd /application/examples/t_ecdsa/src/t_ecdsa_frontend
pnpm test
```

### UIモードでテストを実行

```bash
pnpm test:ui
```

### 一度だけテストを実行（CI用）

```bash
pnpm test:run
```

## テストファイル

- `testHelper.ts`: ICPキャニスターに接続するためのヘルパー関数
- `ethereum-sign.test.ts`: Ethereum署名と検証のテストスイート

## トラブルシューティング

### キャニスターIDが見つからないエラー

```
Error: CANISTER_ID_T_ECDSA_BACKEND is not set
```

解決方法:
1. `dfx deploy t_ecdsa_backend`でキャニスターをデプロイ
2. `dfx generate`でTypeScript宣言ファイルと環境変数を生成

### Root keyの取得に失敗

```
Unable to fetch root key
```

解決方法:
1. `dfx start`でローカルレプリカが起動していることを確認
2. `http://127.0.0.1:4943`にアクセスできることを確認

### タイムアウトエラー

ICPキャニスターの`signWithEthereum`はECDSA署名のためにthreshold署名を実行するため、時間がかかる場合があります。`vitest.config.ts`の`testTimeout`を増やすことで対応できます。

## 参考資料

- [viem公式ドキュメント](https://viem.sh/)
- [viem署名関連API](https://viem.sh/docs/actions/wallet/signMessage)
- [viem検証関連API](https://viem.sh/docs/utilities/verifyMessage)
- [DFinity Agent JS](https://github.com/dfinity/agent-js)

