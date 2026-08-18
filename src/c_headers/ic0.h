// Functions that can be imported from the ic0 wasm runtime
// This header is imported by both C & C++ code
// See: https://isocpp.org/wiki/faq/mixing-c-and-cpp#include-c-hdrs-personal

#ifdef __cplusplus

// only include this in C++ files
// Ensure the WASI polyfill library is initialized first
#include "ic_wasi_polyfill.h"

extern "C" {
#endif

#pragma once

#include <stdint.h>

#include "wasm_symbol.h"

// See:
// https://internetcomputer.org/docs/current/references/ic-interface-spec#system-api-imports

// Message API
uint32_t ic0_msg_arg_data_size()
    WASM_SYMBOL_IMPORTED("ic0", "msg_arg_data_size");

void ic0_msg_arg_data_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_arg_data_copy");

uint32_t ic0_msg_caller_size() WASM_SYMBOL_IMPORTED("ic0", "msg_caller_size");

void ic0_msg_caller_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_caller_copy");

uint32_t ic0_msg_reject_code() WASM_SYMBOL_IMPORTED("ic0", "msg_reject_code");

uint32_t ic0_msg_reject_msg_size()
    WASM_SYMBOL_IMPORTED("ic0", "msg_reject_msg_size");

void ic0_msg_reject_msg_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_reject_msg_copy");

uint64_t ic0_msg_deadline() WASM_SYMBOL_IMPORTED("ic0", "msg_deadline");

void ic0_msg_reply_data_append(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_reply_data_append");

void ic0_msg_reply() WASM_SYMBOL_IMPORTED("ic0", "msg_reply");

void ic0_msg_reject(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_reject");

// Cycles API (128-bit)
void ic0_msg_cycles_available128(uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "msg_cycles_available128");

void ic0_msg_cycles_refunded128(uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "msg_cycles_refunded128");

void ic0_msg_cycles_accept128(uint64_t max_amount_high, uint64_t max_amount_low, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "msg_cycles_accept128");

void ic0_cycles_burn128(uint64_t amount_high, uint64_t amount_low, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cycles_burn128");

// Canister API
uint32_t ic0_canister_self_size()
    WASM_SYMBOL_IMPORTED("ic0", "canister_self_size");

void ic0_canister_self_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "canister_self_copy");

void ic0_canister_cycle_balance128(uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "canister_cycle_balance128");

void ic0_canister_liquid_cycle_balance128(uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "canister_liquid_cycle_balance128");

uint32_t ic0_canister_status()
    WASM_SYMBOL_IMPORTED("ic0", "canister_status");

uint64_t ic0_canister_version()
    WASM_SYMBOL_IMPORTED("ic0", "canister_version");

// Subnet API
uint32_t ic0_subnet_self_size()
    WASM_SYMBOL_IMPORTED("ic0", "subnet_self_size");

void ic0_subnet_self_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "subnet_self_copy");

// Message method name API
uint32_t ic0_msg_method_name_size()
    WASM_SYMBOL_IMPORTED("ic0", "msg_method_name_size");

void ic0_msg_method_name_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "msg_method_name_copy");

void ic0_accept_message() WASM_SYMBOL_IMPORTED("ic0", "accept_message");

// Call API
void ic0_call_new(uint32_t callee_src, uint32_t callee_size, uint32_t name_src,
                  uint32_t name_size, uint32_t reply_fun, uint32_t reply_env,
                  uint32_t reject_fun, uint32_t reject_env)
    WASM_SYMBOL_IMPORTED("ic0", "call_new");

void ic0_call_on_cleanup(uint32_t fun, uint32_t env)
    WASM_SYMBOL_IMPORTED("ic0", "call_on_cleanup");

void ic0_call_data_append(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "call_data_append");

void ic0_call_with_best_effort_response(uint32_t timeout_seconds)
    WASM_SYMBOL_IMPORTED("ic0", "call_with_best_effort_response");

void ic0_call_cycles_add128(uint64_t amount_high, uint64_t amount_low)
    WASM_SYMBOL_IMPORTED("ic0", "call_cycles_add128");

uint32_t ic0_call_perform() WASM_SYMBOL_IMPORTED("ic0", "call_perform");

// Stable Memory API (64-bit)
uint64_t ic0_stable64_size() WASM_SYMBOL_IMPORTED("ic0", "stable64_size");

uint64_t ic0_stable64_grow(uint64_t new_pages)
    WASM_SYMBOL_IMPORTED("ic0", "stable64_grow");

void ic0_stable64_write(uint64_t offset, uint64_t src, uint64_t size)
    WASM_SYMBOL_IMPORTED("ic0", "stable64_write");

void ic0_stable64_read(uint64_t dst, uint64_t offset, uint64_t size)
    WASM_SYMBOL_IMPORTED("ic0", "stable64_read");

// Certified Data API
void ic0_certified_data_set(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "certified_data_set");

uint32_t ic0_data_certificate_present()
    WASM_SYMBOL_IMPORTED("ic0", "data_certificate_present");

uint32_t ic0_data_certificate_size()
    WASM_SYMBOL_IMPORTED("ic0", "data_certificate_size");

void ic0_data_certificate_copy(uint32_t dst, uint32_t off, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "data_certificate_copy");

// Time API
uint64_t ic0_time() WASM_SYMBOL_IMPORTED("ic0", "time");

// Global Timer API
uint64_t ic0_global_timer_set(uint64_t timestamp)
    WASM_SYMBOL_IMPORTED("ic0", "global_timer_set");

// Performance Counter API
uint64_t ic0_performance_counter(uint32_t counter_type)
    WASM_SYMBOL_IMPORTED("ic0", "performance_counter");

// Controller API
uint32_t ic0_is_controller(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "is_controller");

// Replicated Execution API
uint32_t ic0_in_replicated_execution()
    WASM_SYMBOL_IMPORTED("ic0", "in_replicated_execution");

// Cost Calculation APIs
void ic0_cost_call(uint64_t method_name_size, uint64_t payload_size, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_call");

void ic0_cost_create_canister(uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_create_canister");

void ic0_cost_http_request(uint64_t request_size, uint64_t max_res_bytes, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_http_request");

uint32_t ic0_cost_sign_with_ecdsa(uint32_t src, uint32_t size, uint32_t ecdsa_curve, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_sign_with_ecdsa");

uint32_t ic0_cost_sign_with_schnorr(uint32_t src, uint32_t size, uint32_t algorithm, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_sign_with_schnorr");

uint32_t ic0_cost_vetkd_derive_encrypted_key(uint32_t src, uint32_t size, uint32_t vetkd_curve, uint32_t dst)
    WASM_SYMBOL_IMPORTED("ic0", "cost_vetkd_derive_encrypted_key");

// Debug API
void ic0_debug_print(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "debug_print");

// Trap API
[[noreturn]] void ic0_trap(uint32_t src, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "trap");

// Environment Variables API
uint32_t ic0_env_var_count()
    WASM_SYMBOL_IMPORTED("ic0", "env_var_count");

uint32_t ic0_env_var_name_size(uint32_t index)
    WASM_SYMBOL_IMPORTED("ic0", "env_var_name_size");

void ic0_env_var_name_copy(uint32_t index, uint32_t dst, uint32_t offset,
                           uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "env_var_name_copy");

uint32_t ic0_env_var_name_exists(uint32_t name_src, uint32_t name_size)
    WASM_SYMBOL_IMPORTED("ic0", "env_var_name_exists");

uint32_t ic0_env_var_value_size(uint32_t name_src, uint32_t name_size)
    WASM_SYMBOL_IMPORTED("ic0", "env_var_value_size");

void ic0_env_var_value_copy(uint32_t name_src, uint32_t name_size,
                            uint32_t dst, uint32_t offset, uint32_t size)
    WASM_SYMBOL_IMPORTED("ic0", "env_var_value_copy");

#ifdef __cplusplus
}
#endif
