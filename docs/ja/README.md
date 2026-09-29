Rust製ic0  
https://github.com/dfinity/cdk-rs/blob/main/ic0/src/ic0.rs

C言語のキャニスターを作るサンプル  
https://github.com/dfinity/examples/tree/master/c/reverse

C言語をキャニスターにコンパイルするスクリプト  
https://github.com/ICPorts-labs/chico/blob/main/examples/HelloWorld/build.sh

インターネットコンピュータにおけるC++データ構造の直交永続性：研究  
https://forum.dfinity.org/t/orthogonal-persistence-of-c-data-structures-on-the-internet-computer-a-study/21828

icpp-proのコンパイル設定  
https://github.com/icppWorld/icpp-pro/blob/main/src/icpp/config_default.py

icpp-proのデモソースコード  
https://github.com/icppWorld/icpp-demos

wasi2icのツール  
https://github.com/wasm-forge/wasi2ic

Candidのバイト列をデコードするツール  
https://fxa77-fiaaa-aaaae-aaana-cai.raw.icp0.io/explain

Candid型定義  
https://github.com/dfinity/candid/blob/master/spec/Candid.md#types

Candidテストデータ  
https://github.com/dfinity/candid/tree/master/test

---
## NimからICPにデプロイ可能なWASMを作る手順
### ic-wasi-polyfillのビルド

```sh
git submodule add -f https://github.com/wasm-forge/ic-wasi-polyfill wasm-tools/ic-wasi-polyfill

cd /application/wasm-tools/ic-wasi-polyfill
rustup target add wasm32-wasip1
cargo build --release --target wasm32-wasip1
```
`/application/wasm-tools/ic-wasi-polyfill/target/wasm32-wasip1/release` をNimのビルド時にLinkerに渡す

### NimをWASMにコンパイルする
```sh
cd /application/examples/arg_msg_reply
```

config.nims
```sh
--mm: "orc"
--threads: "off"
--cpu: "wasm32"
--os: "linux"
--nomain
--cc: "clang" # コンパイラ：clang を利用
--define: "useMalloc"
--nimcache: "./dist"

# WASI ターゲットだが、icpp-pro のように自己完結型にするために静的リンクを強制
switch("passC", "-target wasm32-wasip1")
switch("passL", "-target wasm32-wasip1")
switch("passL", "-static") # 必要なライブラリ群を静的にリンクする
switch("passL", "-nostartfiles") # 標準のスタートアップコードをリンクしない
switch("passL", "-Wl,--no-entry") # エントリーポイント処理を行わない
switch("passC", "-fno-exceptions")

# ic wasi polyfill のパス指定
switch("passL", "-L/application/wasm-tools/ic-wasi-polyfill/target/wasm32-wasip1/release")
switch("passL", "-lic_wasi_polyfill")

# ic0.h のパス指定
switch("passC", "-I" & "/application/src/nim_ic_cdk/c_headers")
switch("passL", "-L" & "/application/src/nim_ic_cdk/c_headers")

# WASI SDK の sysroot / include 指定
let wasiSysroot = "/root/wasi-sdk-25.0-x86_64-linux/share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

# WASI でのエミュレーション設定
switch("passC", "-D_WASI_EMULATED_SIGNAL")
switch("passL", "-lwasi-emulated-signal")
```

build.sh
```sh
#!/bin/bash
rm -fr ./*.wasm
rm -fr ./*.wat

echo "nim c -d:release -o:wasi.wasm src/arg_msg_reply_backend/main.nim"
nim c -d:release -o:wasi.wasm src/arg_msg_reply_backend/main.nim

echo "wasi2ic wasi.wasm main.wasm"
wasi2ic wasi.wasm main.wasm
rm -f wasi.wasm
```

dfx.json
```json
{
  "canisters": {
    "arg_msg_reply_backend": {
      "candid": "arg_msg_reply.did",
      "package": "arg_msg_reply_backend",
      "build": "build.sh",
      "main": "src/arg_msg_reply_backend/main.nim",
      "wasm": "main.wasm",
      "type": "custom",
      "metadata": [
        {
          "name": "candid:service"
        }
      ]
    },
  },
  "defaults": {
    "build": {
      "args": "",
      "packtool": ""
    }
  },
  "output_env_file": ".env",
  "version": 1
}
```

- [dfx.json](./examples/arg_msg_reply/dfx.json) を作成 
  - 参考 https://internetcomputer.org/docs/building-apps/developer-tools/dfx-json#full-list-of-configuration-options
- dfxを起動 `dfx stop && dfx start --clean --host 0.0.0.0:4943 --background`
- canisterを作成 `dfx canister create arg_msg_reply_backend`
- `dfx deploy arg_msg_reply_backend`
- 実行 `dfx canister call --query arg_msg_reply_backend greet '("world")'`

### Candid encodeされたレスポンスの取得

キャニスターをcallする際に`--output raw`オプションを付けることで、レスポンスをCandid encodeされたバイト列として取得できます：

```bash
# 通常の実行（デコードされた結果）
dfx canister call http_outcall_args_motoko_backend httpRequestArgs

# Candid encodeされたバイト列で取得
dfx canister call http_outcall_args_motoko_backend httpRequestArgs --output raw
```

**出力例**:
```bash
# 通常の実行結果
(
  record {
    url = "https://api.exchange.coinbase.com/products/ICP-USD/candles?start=1682978460&end=1682978460&granularity=60";
    method = variant { get };
    max_response_bytes = null;
    body = null;
    transform = null;
    headers = vec { record { value = "price-feed"; name = "User-Agent" } };
    is_replicated = opt false;
  },
)

# --output raw での実行結果
4449444c0d6c07efd6e40271e1edeb4a07e8d6d8930106a2f5ed880401ecdaccac0408c6a4a198060390f8f6fc09056e026d7b6d046c02f1fee18d0371cbe4fdc704716e7e6e7d6b079681ba027fcfc5d5027fa0d2aca8047fe088f2d2047fab80e3d6067fc88ddcea0b7fdee6f8ff0d7f6e096c0298d6caa2010aefabdecb01026a010b010c01016c02efabdecb010281ddb2900a0c6c03b2ceef2f7da2f5ed880402c6a4a198060301006968747470733a2f2f6170692e65786368616e67652e636f696e626173652e636f6d2f70726f64756374732f4943502d5553442f63616e646c65733f73746172743d3136383239373834363026656e643d31363832393738343630266772616e756c61726974793d363000000000010a70726963652d666565640a557365722d4167656e740100
```

**用途**:
- **デバッグ**: Candid形式の正確性を検証
- **型変換テスト**: Nim実装でのCandidRecord変換の検証
- **IC Management Canister通信**: HTTP Outcall等での正確なメッセージ形式確認
- **開発支援**: 異なる言語間での型システム一貫性確認


---

## 検証のための手順

### Motokoで作ったWASMのWAT形式を確認する
WASMにビルド

```sh
cd /application/src/dfx_hello
dfx stop && dfx start --clean --host 0.0.0.0:4943 --background
dfx canister create dfx_hello_backend
dfx build
```

`/application/src/dfx_hello/.dfx/local/canisters/dfx_hello_backend/dfx_hello_backend.wasm` が出力される  

WASMをWATに変換する
```sh
cd /application/src/dfx_hello
wasm2wat .dfx/local/canisters/dfx_hello_backend/dfx_hello_backend.wasm -o dfx_hello_backend.wat
```

`/application/src/dfx_hello/dfx_hello_backend.wat` が出力される


### RustのICPインターフェースからアーカイブファイルを作る

```sh
cd /application/src/rust_ic0
rustup target add wasm32-wasip1
cargo build --release --target wasm32-wasip1
```

`/application/src/rust_ic0/target/wasm32-unknown-unknown/release/libic0.a` が作られる
