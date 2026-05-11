# Message inspection
# https://internetcomputer.org/docs/motoko/main/writing-motoko/message-inspection

import ./ic_types/candid_types
import ./ic_types/ic_principal
import ./ic0/ic0

type Msg* = object

proc caller*(_:type Msg): Principal =
  let size = ic0_msg_caller_size()
  var caller = newSeq[byte](size)
  if size > 0:
    ic0_msg_caller_copy(ptrToInt(addr caller[0]), 0, size)
  return Principal.fromBlob(caller)
