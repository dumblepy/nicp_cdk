#!/usr/bin/env bash
set -euo pipefail
set -x

# Set TERM to prevent dfx color output errors in CI/test environments
# export TERM=xterm-256color

# Run make to start dfx in background
nimble install -y
nicp cHeaders
dfx stop
rm -rf /application/examples/*/.dfx
dfx start --clean --background --host 0.0.0.0:4943 --domain localhost --domain 0.0.0.0
dfx ping
cd /application/solidity
forge install
cd /application/solidity/script/Counter
./deployCounter.sh
cd /application
nimble test
