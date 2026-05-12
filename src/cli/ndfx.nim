import ./ndfx_functions/new_impl
import ./ndfx_functions/c_headers_impl
import ./ndfx_functions/development_build_impl
import ./ndfx_functions/production_build_impl
import ./ndfx_functions/network_impl

when isMainModule:
  import cligen
  dispatchMulti(
    [new_impl.new], [c_headers_impl.cHeaders],
    [development_build_impl.developmentBuild], [production_build_impl.productionBuild],
    [network_impl.network]
  )
