#!/bin/bash

# Candid互換性テストの実行スクリプト

set -e

echo "=== Candid Encoding Compatibility Test ==="

# プロジェクトのルートディレクトリに移動
cd "$(dirname "$0")"

echo "Stopping any running DFX processes..."
dfx stop

echo "Starting local DFX replica..."
dfx start --background

# Motokoプロジェクトのビルドとデプロイ
echo "Building and deploying Motoko canister..."
cd motoko
dfx deploy
MOTOKO_CANISTER_ID=$(dfx canister id motoko_backend)
echo "Motoko canister deployed with ID: $MOTOKO_CANISTER_ID"
cd ..

# Nimプロジェクトのビルドとデプロイ
echo "Building and deploying Nim canister..."
cd nim
dfx deploy
NIM_CANISTER_ID=$(dfx canister id nim_backend)
echo "Nim canister deployed with ID: $NIM_CANISTER_ID"
cd ..

echo "Both canisters deployed successfully!"
echo ""

# 基本的な動作テスト
echo "=== Basic Functionality Tests ==="

echo "Testing Motoko canister..."
cd motoko
dfx canister call motoko_backend bool '()' || echo "Warning: Motoko bool test failed"
dfx canister call motoko_backend int '()' || echo "Warning: Motoko int test failed"
dfx canister call motoko_backend text '()' || echo "Warning: Motoko text test failed"
cd ..

echo "Testing Nim canister..."
cd nim
dfx canister call nim_backend bool '()' || echo "Warning: Nim bool test failed"
dfx canister call nim_backend int '()' || echo "Warning: Nim int test failed"
dfx canister call nim_backend text '()' || echo "Warning: Nim text test failed"
cd ..

echo ""
echo "=== Running Compatibility Tests ==="

# Nimテストを実行
cd ../../..
nim c -r tests/test_encode_response.nim

echo ""
echo "=== Test Summary ==="
echo "Motoko canister ID: $MOTOKO_CANISTER_ID"
echo "Nim canister ID: $NIM_CANISTER_ID"
echo "Test completed!"

# クリーンアップオプション（コメントアウト）
# echo "Stopping DFX..."
# dfx stop
