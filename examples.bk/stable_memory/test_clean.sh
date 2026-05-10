#!/bin/bash
DFX="/root/.local/share/dfx/bin/dfx"

echo "=== Reset all databases ==="
$DFX canister call stable_memory_backend int_set '(0)'
$DFX canister call stable_memory_backend uint_set '(0)'
$DFX canister call stable_memory_backend string_set '("")'
$DFX canister call stable_memory_backend bool_set '(false)'
$DFX canister call stable_memory_backend float_set '(0.0 : float32)'
$DFX canister call stable_memory_backend double_set '(0.0 : float64)'
$DFX canister call stable_memory_backend char_set '(0)'
$DFX canister call stable_memory_backend byte_set '(0)'
$DFX canister call stable_memory_backend seqInt_reset '()'
$DFX canister call stable_memory_backend table_reset '()'

echo ""
echo "=== Test upgrade preserves stable memory scenario ==="
$DFX canister call stable_memory_backend seqInt_reset '()'
$DFX canister call stable_memory_backend table_reset '()'

echo "Setting int to 123"
$DFX canister call stable_memory_backend int_set '(123)'

echo "Adding 7 to seqInt"
$DFX canister call stable_memory_backend seqInt_set '(7)'

echo "Adding 8 to seqInt"
$DFX canister call stable_memory_backend seqInt_set '(8)'

echo "Setting principal -> 'upgrade' in table"
$DFX canister call stable_memory_backend table_setFor "(principal \"aaaaa-aa\", \"upgrade\")"

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
echo "table_getFor(aaaaa-aa):"
$DFX canister call stable_memory_backend table_getFor "(principal \"aaaaa-aa\")"

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
echo "table_getFor(aaaaa-aa):"
$DFX canister call stable_memory_backend table_getFor "(principal \"aaaaa-aa\")"
