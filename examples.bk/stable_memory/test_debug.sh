#!/bin/bash
DFX="/root/.local/share/dfx/bin/dfx"

echo "=== Step 1: Deployment (fresh code) ==="
$DFX deploy stable_memory_backend -y 2>&1 | tail -5

echo ""
echo "=== Step 2: Read initial int_get value ==="
$DFX canister call stable_memory_backend int_get '()' 2>&1

echo ""
echo "=== Step 3: Set int to 999 ==="
$DFX canister call stable_memory_backend int_set '(999)' 2>&1

echo ""
echo "=== Step 4: Verify int_get after set ==="
$DFX canister call stable_memory_backend int_get '()' 2>&1

echo ""
echo "=== Done ==="
