#!/bin/bash
DFX="/root/.local/share/dfx/bin/dfx"

echo "=== Deploy ==="
$DFX deploy stable_memory_backend -y 2>&1 | tail -3

echo ""
echo "=== Reset databases ==="
$DFX canister call stable_memory_backend seqInt_reset '()'

echo ""
echo "=== Set seqInt data ==="
echo "seqInt_set(7)"
$DFX canister call stable_memory_backend seqInt_set '(7)'
echo "seqInt_set(8)"
$DFX canister call stable_memory_backend seqInt_set '(8)'
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'

echo ""
echo "=== Before upgrade ==="
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'

echo ""
echo "=== Upgrade ==="
$DFX canister install --mode=upgrade stable_memory_backend 2>&1 | tail -3

echo ""
echo "=== After upgrade (before reset) ==="
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'

echo ""
echo "=== After seqInt_reset ==="
$DFX canister call stable_memory_backend seqInt_reset '()'
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'

echo ""
echo "=== Set new data ==="
echo "seqInt_set(100)"
$DFX canister call stable_memory_backend seqInt_set '(100)'
echo "seqInt_set(200)"
$DFX canister call stable_memory_backend seqInt_set '(200)'
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'
