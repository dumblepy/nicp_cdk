import ./wasm_build

proc dev*(): int =
  ## Build WASM only for local iteration.
  compileWasm(release = false)

proc developmentBuild*(): int =
  ## Backward-compatible alias for `ndfx dev`.
  dev()
