import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/ic_types/ic_principal
include ./controller


proc getPublicKey*() {.update.} = discard getPublicKeyImpl()


proc deriveKey*() {.update.} = discard deriveKeyImpl()


proc deriveKeyWithTransportPublicKey*() {.update.} = discard deriveKeyWithTransportPublicKeyImpl()


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


proc createPrivateNote*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let ciphertext = request.getStr(1)
  let nonce = request.getStr(2)
  let aad = request.getStr(3)
  let keyVersion = uint(request.getNat64(4))
  createPrivateNoteImpl(noteId, ciphertext, nonce, aad, keyVersion)


proc describePrivateNote*() {.update.} =
  let request = Request.new()
  let owner = request.getPrincipal(0)
  let noteId = request.getStr(1)
  describePrivateNoteImpl(owner, noteId)


proc rotatePrivateNoteKey*() {.update.} =
  let request = Request.new()
  let owner = request.getPrincipal(0)
  let noteId = request.getStr(1)
  let keyVersion = uint(request.getNat64(2))
  rotatePrivateNoteKeyImpl(owner, noteId, keyVersion)


proc derivePrivateNoteKey*() {.update.} =
  let request = Request.new()
  let owner = request.getPrincipal(0)
  let noteId = request.getStr(1)
  let transportPublicKeyText = request.getStr(2)
  discard derivePrivateNoteKeyImpl(owner, noteId, transportPublicKeyText)


proc createSharedNote*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let ciphertext = request.getStr(1)
  let nonce = request.getStr(2)
  let aad = request.getStr(3)
  let keyVersion = uint(request.getNat64(4))
  createSharedNoteImpl(noteId, ciphertext, nonce, aad, keyVersion)


proc describeSharedNote*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  describeSharedNoteImpl(noteId)


proc grantSharedNoteAccess*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let principal = request.getPrincipal(1)
  grantSharedNoteAccessImpl(noteId, principal)


proc revokeSharedNoteAccess*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let principal = request.getPrincipal(1)
  revokeSharedNoteAccessImpl(noteId, principal)


proc rotateSharedNoteKey*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let keyVersion = uint(request.getNat64(1))
  rotateSharedNoteKeyImpl(noteId, keyVersion)


proc deriveSharedNoteKey*() {.update.} =
  let request = Request.new()
  let noteId = request.getStr(0)
  let transportPublicKeyText = request.getStr(1)
  discard deriveSharedNoteKeyImpl(noteId, transportPublicKeyText)
