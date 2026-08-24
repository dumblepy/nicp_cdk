import std/os

--mm: "orc"
--threads: "off"
--cpu: "wasm32"
--os: "linux"
--nomain
--cc: "clang"
--define: "useMalloc"

switch("define", "wasi")
switch("define", "rustcryptoWasi")

# Enforce static linking for the WASI target to make it self-contained.
switch("passC", "-target wasm32-wasi")
switch("passL", "-target wasm32-wasi")
switch("passL", "-static")
switch("passL", "-nostartfiles")
switch("passL", "-Wl,--no-entry")
switch("passC", "-fno-exceptions")

# Rust crypto libraries may have multiple definitions of the same symbol.
switch("passL", "-Wl,--allow-multiple-definition")

when defined(release):
  switch("passC", "-Os")
  switch("passC", "-flto")
  switch("passL", "-flto")

let cHeadersPath = "/root/.ic-c-headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)

let icWasiPolyfillPath = getEnv("IC_WASI_POLYFILL_PATH")
switch("passL", "-L" & icWasiPolyfillPath)
switch("passL", "-lic_wasi_polyfill")

let wasiSysroot = getEnv("WASI_SDK_PATH") / "share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

switch("passC", "-D_WASI_EMULATED_SIGNAL")
switch("passL", "-lwasi-emulated-signal")
