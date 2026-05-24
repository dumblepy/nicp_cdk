import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/ic_types/ic_principal
include ./controller


proc storePrivateKv*() {.update.} =
  let request = Request.new()
  let ciphertext = request.getBlob(0)
  let keyVersion = uint(request.getNat64(1))
  storePrivateKvImpl(ciphertext, keyVersion)


proc fetchPrivateKv*() {.update.} = fetchPrivateKvImpl()


proc derivePrivateKvKey*() {.update.} =
  let request = Request.new()
  let transportPublicKeyText = request.getStr(0)
  let keyVersion = uint(request.getNat64(1))
  discard derivePrivateKvKeyImpl(transportPublicKeyText, keyVersion)
