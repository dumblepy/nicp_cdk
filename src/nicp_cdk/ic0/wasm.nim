import std/macros

# Reference
# https://github.com/yglukhov/wasmrt/blob/master/wasmrt.nim#L4-L10

macro exportwasm*(p: untyped): untyped =
  expectKind(p, nnkProcDef)
  result = p
  let name = $p.name
  let codegenPragma = "__attribute__ ((export_name (\"" & name & "\"))) $# $#$#"
  result.addPragma(newColonExpr(ident"codegenDecl", newLit(codegenPragma)))
  result.addPragma(ident"exportc")


macro query*(p: untyped): untyped =
  ## "canister_query {p}"
  expectKind(p, nnkProcDef)
  result = p
  let name = $p.name
  let codegenPragma = "__attribute__ ((export_name (\"canister_query " &
      name & "\"))) $# $#$#"
  result.addPragma(newColonExpr(ident"codegenDecl", newLit(codegenPragma)))
  result.addPragma(ident"exportc")


macro update*(p: untyped): untyped =
  ## "canister_update {p}"
  expectKind(p, nnkProcDef)
  result = p
  let name = $p.name
  let codegenPragma = "__attribute__ ((export_name (\"canister_update " &
      name & "\"))) $# $#$#"
  result.addPragma(newColonExpr(ident"codegenDecl", newLit(codegenPragma)))
  result.addPragma(ident"exportc")


when not defined(nicpDisableWasiPolyfill):
  {.emit: """
#include <stddef.h>

#define __IMPORT(module, name) __attribute__((__import_module__(#module), __import_name__(#name)))
#define __EXPORT(name) __attribute__((__export_name__(#name)))

// Initialize the WASI polyfill library first.
extern void raw_init(char* p, size_t len) __IMPORT(polyfill, raw_init);

// This function will be called automatically at startup.
__attribute__((constructor))
static void initWasiPolyfill(void) {
    raw_init(NULL, 0);
}
""".}
