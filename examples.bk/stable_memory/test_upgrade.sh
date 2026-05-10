#!/bin/bash

DFX="/root/.local/share/dfx/bin/dfx"

echo "=== Test 1: Set values ==="
$DFX canister call stable_memory_backend seqInt_reset '()'
echo "seqInt_reset completed"

$DFX canister call stable_memory_backend int_set '(123)'
echo "int_set(123) completed"

$DFX canister call stable_memory_backend seqInt_set '(7)'
echo "seqInt_set(7) completed"

$DFX canister call stable_memory_backend seqInt_set '(8)'
echo "seqInt_set(8) completed"

echo ""
echo "=== Before upgrade ==="
echo "int_get:"
$DFX canister call stable_memory_backend int_get '()'
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'

echo ""
echo "=== Upgrading ==="
$DFX canister install --mode=upgrade stable_memory_backend

echo ""
echo "=== After upgrade ==="
echo "int_get:"
$DFX canister call stable_memory_backend int_get '()'
echo "seqInt_len:"
$DFX canister call stable_memory_backend seqInt_len '()'
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'
