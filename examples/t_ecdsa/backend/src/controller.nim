import std/asyncdispatch
import std/strutils
import ../../../../src/nicp_cdk
import ../../../../src/nicp_cdk/ic_types/candid_types
import ../../../../src/nicp_cdk/ic_types/ic_record
import ./usecase


proc getNewPublicKey*() {.async.} =
  let caller = Msg.caller()

  try:
    let publicKey = await usecase.getNewPublicKey(caller)
    reply(publicKey)
  except ValueError as e:
    reject("Failed to get public key: " & e.msg)


proc getPublicKey*() =
  let caller = Msg.caller()
  try:
    let publicKey = usecase.getPublicKey(caller)
    reply(publicKey)
  except Exception as e:
    reject("Failed to get public key: " & e.msg)


proc signWithEcdsa*() {.async.} =
  let request = Request.new()
  let message = request.getStr(0)
  let caller = Msg.caller()

  discard await usecase.getNewPublicKey(caller)
  
  try:
    let signature = await usecase.signWithEcdsa(caller, message)
    reply(signature)
  except Exception as e:
    reject("Failed to sign with ECDSA: " & e.msg)


proc verifyWithEcdsa*() =
  let request = Request.new()
  let argRecord = request.getRecord(0)
  let message = argRecord["message"].getStr()
  let signature = argRecord["signature"].getStr()
  let publicKey = argRecord["publicKey"].getStr()

  try:
    let isValid = usecase.verifyWithEcdsa(message, signature, publicKey)
    reply(isValid)
  except Exception as e:
    reject("Failed to verify with ECDSA: " & e.msg)


proc getEvmAddress*() =
  let caller = Msg.caller()
  try:
    let evmAddress = usecase.getEvmAddress(caller)
    reply(evmAddress)
  except Exception as e:
    reject("Failed to get EVM address: " & e.msg)


proc signWithEthereum*() {.async.} =
  let request = Request.new()
  let message = request.getStr(0)
  let caller = Msg.caller()

  discard await usecase.getNewPublicKey(caller)
  
  try:
    let signature = await usecase.signWithEthereum(caller, message)
    reply(signature)
  except Exception as e:
    reject("Failed to sign with Ethereum: " & e.msg)


proc verifyWithEthereum*() =
  let request = Request.new()
  let argRecord = request.getRecord(0)
  let message = argRecord["message"].getStr()
  let signature = argRecord["signature"].getStr()
  let ethereumAddress = argRecord["ethereumAddress"].getStr()

  try:
    let isValid = usecase.verifyWithEthereum(message, signature, ethereumAddress)
    reply(isValid)
  except Exception as e:
    reject("Failed to verify with Ethereum: " & e.msg)


proc signWithEvmWallet*() {.async.} =
  let request = Request.new()
  let message = request.getBlob(0)
  let caller = Msg.caller()

  discard await usecase.getNewPublicKey(caller)
  
  try:
    let signature = await usecase.signWithEvmWallet(caller, message)
    reply(signature)
  except Exception as e:
    reject("Failed to sign with EVM wallet: " & e.msg)
