import ./functions/new_impl
import ./functions/c_headers_impl
import ./functions/development_build_impl
import ./functions/production_build_impl
import ./functions/network_impl

when isMainModule:
  import cligen
  dispatchMulti(
    [new_impl.new], [c_headers_impl.cHeaders],
    [development_build_impl.dev], [production_build_impl.build],
    [network_impl.network]
  )
