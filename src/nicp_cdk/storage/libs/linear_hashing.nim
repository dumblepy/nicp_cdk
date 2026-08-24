## Persistent linear-hashing state transitions.
type LinearHashState* = object
  level*, split*: uint32

proc validate(state: LinearHashState) {.inline.} =
  ## `split` is persisted as uint32, so level 32 is the largest representable
  ## round. Keeping this check at the state boundary prevents a corrupt header
  ## from turning into an overflowing split counter or shift operation.
  if state.level > 32 or state.split >= (1'u64 shl state.level):
    raise newException(ValueError, "invalid linear hash state")

proc bucketIndex*(state: LinearHashState, hash: uint64): uint64 =
  state.validate
  let baseMask = (1'u64 shl state.level) - 1
  result = hash and baseMask
  if result < uint64(state.split):
    result = hash and ((1'u64 shl (state.level + 1)) - 1)

proc bucketCount*(state: LinearHashState): uint64 =
  state.validate
  (1'u64 shl state.level) + uint64(state.split)

proc splitBucket*(state: LinearHashState): uint64 =
  state.validate
  uint64(state.split)

proc advanceSplit*(state: var LinearHashState) =
  state.validate
  if state.level == 32 and state.split == high(uint32):
    raise newException(ValueError, "linear hash level cannot grow further")
  inc state.split
  if uint64(state.split) == (1'u64 shl state.level):
    if state.level == 32:
      raise newException(ValueError, "linear hash level cannot grow further")
    inc state.level
    state.split = 0
