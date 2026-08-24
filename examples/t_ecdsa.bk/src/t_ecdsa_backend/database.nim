import std/tables
import ../../../../src/nicp_cdk/ic_types/ic_principal

var keys = initTable[Principal, seq[uint8]]()

proc hasKey*(caller: Principal): bool =
  return keys.hasKey(caller)

proc getPublicKey*(caller: Principal): seq[uint8] =
  if hasKey(caller):
    return keys[caller]
  else:
    return @[]

proc setPublicKey*(caller: Principal, publicKey: seq[uint8]) =
  keys[caller] = publicKey
