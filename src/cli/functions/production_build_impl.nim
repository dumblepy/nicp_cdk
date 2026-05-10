import ./wasm_build

proc build*(): int =
  ## Build WASM only with -d:release (production).
  compileWasm(release = true)

proc productionBuild*(): int =
  ## Backward-compatible alias for `ndfx build`.
  build()
