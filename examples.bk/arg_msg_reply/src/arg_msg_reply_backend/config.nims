import std/os

--mm: "orc"
--threads: "off"
--cpu: "wasm32"
--os: "linux"
--nomain
--cc: "clang"
--define: "useMalloc"

# Enforce static linking for the WASI target to make it self-contained, similar to icpp-pro
switch("passC", "-target wasm32-wasi")
switch("passL", "-target wasm32-wasi")
switch("passL", "-static") # Statically link necessary libraries
switch("passL", "-nostartfiles") # Do not link standard startup files
switch("passL", "-Wl,--no-entry") # Do not enforce an entry point
switch("passC", "-fno-exceptions") # Do not use exceptions

# optimize
when defined(release):
  switch("passC", "-Os") # optimize for size
  switch("passC", "-flto") # link time optimization for compiler
  switch("passL", "-flto") # link time optimization for linker

# ic0.h path
let cHeadersPath = "/root/.ic-c-headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)

# ic wasi polyfill path
let icWasiPolyfillPath = getEnv("IC_WASI_POLYFILL_PATH")
switch("passL", "-L" & icWasiPolyfillPath)
switch("passL", "-lic_wasi_polyfill")

# WASI SDK sysroot / include
let wasiSysroot = getEnv("WASI_SDK_PATH") / "share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

# WASI emulation settings
switch("passC", "-D_WASI_EMULATED_SIGNAL")
switch("passL", "-lwasi-emulated-signal")
