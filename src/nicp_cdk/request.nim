import std/options
import ./ic_types/candid_types
import ./ic_types/candid_message/candid_decode
import ./ic_types/ic_principal
import ./ic_types/ic_record
import ./ic0/ic0


type Request* = object
  values: seq[CandidValue]

proc new*(_:type Request): Request =
  let n = ic0_msg_arg_data_size()
  var data = newSeq[byte](n)
  ic0_msg_arg_data_copy(ptrToInt(addr data[0]), 0, n)
  let decodedResult = decodeCandidMessage(data)
  return Request(values: decodedResult.values)


# Get the argument at the specified index as a bool
proc getBool*(self:Request, index:int): bool =
  ## Get the argument at the specified index as a bool
  assert self.values[index].kind == ctBool
  return self.values[index].boolVal


proc getNat*(self:Request, index:int): uint =
  ## Get the argument at the specified index as a nat
  assert self.values[index].kind == ctNat
  return self.values[index].natVal


proc getNat8*(self:Request, index:int): uint8 =
  ## Get the argument at the specified index as a nat8
  assert self.values[index].kind == ctNat8, "Expected nat8 type, got: " & $self.values[index].kind
  return self.values[index].nat8Val


proc getNat16*(self:Request, index:int): uint16 =
  ## Get the argument at the specified index as a nat16
  assert self.values[index].kind == ctNat16, "Expected nat16 type, got: " & $self.values[index].kind
  return self.values[index].nat16Val


proc getNat32*(self:Request, index:int): uint32 =
  ## Get the argument at the specified index as a nat32
  assert self.values[index].kind == ctNat32, "Expected nat32 type, got: " & $self.values[index].kind
  return self.values[index].nat32Val

proc getNat32Compatible*(self: Request, index: int): uint32 =
  ## Get a key represented as either Candid `nat32` or `nat`.
  ##
  ## Storage APIs commonly use a fixed-width uint32 key, while older callers
  ## may still send an unbounded `nat`.  Accept both forms explicitly instead
  ## of relying on an assertion that would trap the canister without context.
  case self.values[index].kind
  of ctNat32:
    result = self.values[index].nat32Val
  of ctNat:
    if self.values[index].natVal > uint(high(uint32)):
      raise newException(ValueError, "nat key exceeds uint32 range")
    result = uint32(self.values[index].natVal)
  else:
    raise newException(ValueError,
      "Expected nat32 or nat key, got: " & $self.values[index].kind)


proc getNat64*(self:Request, index:int): uint64 =
  ## Get the argument at the specified index as a nat64
  assert self.values[index].kind == ctNat64, "Expected nat64 type, got: " & $self.values[index].kind
  return self.values[index].nat64Val


# Get the argument at the specified index as an int
proc getInt*(self:Request, index:int): int =
  ## Get the argument at the specified index as an int
  assert self.values[index].kind == ctInt, "Expected int type, got: " & $self.values[index].kind
  return self.values[index].intVal


# Get the argument at the specified index as an int8
proc getInt8*(self:Request, index:int): int8 =
  ## Get the argument at the specified index as an int8
  assert self.values[index].kind == ctInt8, "Expected int8 type, got: " & $self.values[index].kind
  return self.values[index].int8Val


# Get the argument at the specified index as an int16
proc getInt16*(self:Request, index:int): int16 =
  ## Get the argument at the specified index as an int16
  assert self.values[index].kind == ctInt16, "Expected int16 type, got: " & $self.values[index].kind
  return self.values[index].int16Val


# Get the argument at the specified index as an int32
proc getInt32*(self:Request, index:int): int32 =
  ## Get the argument at the specified index as an int32
  assert self.values[index].kind == ctInt32, "Expected int32 type, got: " & $self.values[index].kind
  return self.values[index].int32Val


# Get the argument at the specified index as an int64
proc getInt64*(self:Request, index:int): int64 =
  ## Get the argument at the specified index as an int64
  assert self.values[index].kind == ctInt64, "Expected int64 type, got: " & $self.values[index].kind
  return self.values[index].int64Val



# Get the argument at the specified index as a float32
proc getFloat*(self:Request, index:int): float32 =
  ## Get the argument at the specified index as a float32
  assert self.values[index].kind == ctFloat32, "Expected float32 type, got: " & $self.values[index].kind
  return self.values[index].float32Val


# Get the argument at the specified index as a float32
proc getFloat32*(self:Request, index:int): float32 =
  ## Get the argument at the specified index as a float32
  assert self.values[index].kind == ctFloat32, "Expected float32 type, got: " & $self.values[index].kind
  return self.values[index].float32Val


# Get the argument at the specified index as a float64
proc getFloat64*(self:Request, index:int): float64 =
  ## Get the argument at the specified index as a float64
  assert self.values[index].kind == ctFloat64, "Expected float64 type, got: " & $self.values[index].kind
  return self.values[index].float64Val


# Get the argument at the specified index as a string
proc getStr*(self:Request, index:int): string =
  ## Get the argument at the specified index as a string
  assert self.values[index].kind == ctText, "Expected text type, got: " & $self.values[index].kind
  return self.values[index].textVal


# Get the argument at the specified index as a Principal
proc getPrincipal*(self:Request, index:int): Principal =
  ## Get the argument at the specified index as a principal
  assert self.values[index].kind == ctPrincipal, "Expected principal type, got: " & $self.values[index].kind
  return self.values[index].principalVal


# Get the argument at the specified index as a blob
proc getBlob*(self:Request, index:int): seq[uint8] =
  ## Get the argument at the specified index as a blob (accepts both ctBlob and ctVec of nat8)
  case self.values[index].kind:
  of ctBlob:
    return self.values[index].blobVal
  of ctVec:
    # If received as vec nat8, construct a byte array from each element
    var arr = newSeq[uint8](self.values[index].vecVal.len)
    for i, val in self.values[index].vecVal:
      assert val.kind == ctNat8, "Vector elements must be nat8 for blob conversion"
      arr[i] = val.nat8Val
    return arr
  else:
    assert false, "Expected blob or vec nat8, got: " & $self.values[index].kind


# Get the argument at the specified index as an Option
proc getOpt*(self:Request, index:int): Option[CandidValue] =
  ## Get the argument at the specified index as an optional value
  assert self.values[index].kind == ctOpt, "Expected opt type, got: " & $self.values[index].kind
  if self.values[index].optVal.isSome():
    return self.values[index].optVal
  else:
    return none(CandidValue)


# Get the argument at the specified index as a Vector
proc getVec*(self:Request, index:int): seq[CandidValue] =
  ## Get the argument at the specified index as a vector
  assert self.values[index].kind == ctVec, "Expected vec type, got: " & $self.values[index].kind
  return self.values[index].vecVal


# Get the argument at the specified index as a Variant
proc getVariant*(self:Request, index:int): CandidVariant =
  ## Get the argument at the specified index as a variant
  assert self.values[index].kind == ctVariant, "Expected variant type, got: " & $self.values[index].kind
  return self.values[index].variantVal


# Get the argument at the specified index as a Function
proc getFunc*(self:Request, index:int): IcFunc =
  ## Get the argument at the specified index as a function
  assert self.values[index].kind == ctFunc, "Expected func type, got: " & $self.values[index].kind
  return self.values[index].funcVal


proc getService*(self:Request, index:int): Principal =
  ## Get the argument at the specified index as a service
  assert self.values[index].kind == ctService, "Expected service type, got: " & $self.values[index].kind
  return self.values[index].serviceVal


proc getEmpty*(self:Request, index:int) =
  ## Get the argument at the specified index as empty (validation only)
  assert self.values[index].kind == ctEmpty, "Expected empty type, got: " & $self.values[index].kind
  # Empty type has no value, only type check is performed


# Get the argument at the specified index as a Record
proc getRecord*(self:Request, index:int): CandidRecord =
  ## Get the argument at the specified index as a record
  assert self.values[index].kind == ctRecord, "Expected record type, got: " & $self.values[index].kind
  return candidValueToCandidRecord(self.values[index])


# ================================================================================
# Enum Type Support Functions
# ================================================================================

proc getEnum*[T: enum](self: Request, index: int, enumType: typedesc[T]): T =
  ## Get the argument at the specified index as an enum value (from Variant)
  if index < 0 or index >= self.values.len:
    raise newException(IndexDefect, "Request index " & $index & " is out of bounds (0.." & $(self.values.len - 1) & ")")
  
  let candidValue = self.values[index]
  if candidValue.kind != ctVariant:
    raise newException(ValueError, 
      "Expected variant type for enum conversion at index " & $index & ", got: " & $candidValue.kind)
  
  try:
    return getEnumValue(candidValue, enumType)
  except ValueError as e:
    raise newException(ValueError, 
      "Failed to convert variant at index " & $index & " to enum type " & $typeof(T) & ": " & e.msg)


# ================================================================================
# Test Helper Functions
# ================================================================================

proc newMockRequest*(values: seq[CandidValue]): Request =
  ## Creates a Request object for testing
  Request(values: values)
