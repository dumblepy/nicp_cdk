#!/usr/bin/env bash
set -euo pipefail
set -x

cleanup_icp_state() {
  while IFS= read -r -d '' manifest; do
    project_dir="$(dirname "$manifest")"
    (cd "$project_dir" && icp network stop >/dev/null 2>&1) || true
  done < <(find /application/examples -name icp.yaml -print0)

  find /application/examples -type d -name .icp -exec rm -rf {} +
}

free_icp_gateway_port() {
  pkill -f 'icp-cli-network-launcher .*--gateway-port 8000' >/dev/null 2>&1 || true
}

trap cleanup_icp_state EXIT

nimble uninstall nicp_cdk -yi >/dev/null 2>&1 || true
nimble install -y
nicp cHeaders

free_icp_gateway_port
cleanup_icp_state

cd /application/solidity
forge install
cd /application/solidity/script/Counter
./deployCounter.sh
cd /application
# Run Testament directly instead of through the Nimble task wrapper.  A failed
# test command exits this script immediately because of `set -e`, so the
# container and GitHub Actions job receive Testament's non-zero status.
testament p "tests/test_*.nim"
testament p "tests/**/test_*.nim"
