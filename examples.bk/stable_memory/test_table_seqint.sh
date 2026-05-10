#!/bin/bash
DFX="/root/.local/share/dfx/bin/dfx"

echo "=== Deploy ==="
$DFX deploy stable_memory_backend -y 2>&1 | tail -3

echo ""
echo "=== Initial seqInt operations ==="
$DFX canister call stable_memory_backend seqInt_reset '()'
$DFX canister call stable_memory_backend seqInt_set '(7)'
$DFX canister call stable_memory_backend seqInt_set '(8)'
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'

echo ""
echo "=== Before table_setFor ==="
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'

echo ""
echo "=== Call table_setFor ==="
$DFX canister call stable_memory_backend table_setFor "(principal \"aaaaa-aa\", \"upgrade\")"

echo ""
echo "=== After table_setFor ==="
echo "seqInt_get(0):"
$DFX canister call stable_memory_backend seqInt_get '(0)'
echo "seqInt_get(1):"
$DFX canister call stable_memory_backend seqInt_get '(1)'

echo ""
echo "=== table_getFor ==="
$DFX canister call stable_memory_backend table_getFor "(principal \"aaaaa-aa\")"
