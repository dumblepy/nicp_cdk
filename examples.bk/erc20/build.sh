#!/bin/bash
rm -fr ./*.wasm
rm -fr ./*.wat

# for debug build
echo "nim c -o:wasi.wasm src/erc20_backend/main.nim"
nim c -o:wasi.wasm src/erc20_backend/main.nim

# for release build
# echo "nim c -d:release -o:wasi.wasm src/erc20_backend/main.nim"
# nim c -d:release -o:wasi.wasm src/erc20_backend/main.nim

echo "wasi2ic wasi.wasm main.wasm"
wasi2ic wasi.wasm main.wasm
rm -f wasi.wasm
