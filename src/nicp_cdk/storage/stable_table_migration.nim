## Incremental, persistent migration from the append-only STBL v1 format.

import std/endians
import ./serialization
import ./memory_view
import ./stable_btree

const
  V1Magic = [byte('S'), byte('T'), byte('B'), byte('L')]
  MigrationMagic = [byte('S'), byte('M'), byte('I'), byte('2')]
  MigrationHeaderSize = 64'u64
  V1HeaderSize = 32'u64

type StableTableMigration* = object
  source*: StableMemoryView
  state*: StableMemoryView
  cursor*, dataEnd*: uint64
  completed*: bool

proc put64(data: var openArray[byte], at: int, value: uint64) =
  var x = value; littleEndian64(addr data[at], addr x)
proc get64(data: openArray[byte], at: int): uint64 =
  littleEndian64(addr result, unsafeAddr data[at])

proc writeState(m: StableTableMigration) =
  var data = newSeq[byte](int(MigrationHeaderSize))
  for i in 0 .. 3: data[i] = MigrationMagic[i]
  data[4] = byte(if m.completed: 1 else: 0)
  data.put64(8, m.cursor); data.put64(16, m.dataEnd)
  m.state.write(0, data)

proc initStableTableMigration*(source, state: StableMemoryView): StableTableMigration =
  ## State must be a view dedicated to this migration and must not overlap the
  ## v1 source or SBT2 destination view.
  result.source = source; result.state = state
  if state.size >= MigrationHeaderSize:
    let data = state.read(0, MigrationHeaderSize)
    var valid = true
    for i in 0 .. 3: valid = valid and data[i] == MigrationMagic[i]
    if valid:
      result.completed = data[4] != 0; result.cursor = data.get64(8); result.dataEnd = data.get64(16)
      if result.cursor < V1HeaderSize or result.cursor > result.dataEnd:
        raise newException(ValueError, "invalid stable table migration cursor")
      return
  if source.size < V1HeaderSize: raise newException(ValueError, "STBL v1 header is missing")
  let header = source.read(0, V1HeaderSize)
  for i in 0 .. 3:
    if header[i] != V1Magic[i]: raise newException(ValueError, "STBL v1 magic is missing")
  var version: uint32; littleEndian32(addr version, unsafeAddr header[4])
  if version != 1'u32: raise newException(ValueError, "unsupported STBL version")
  result.cursor = V1HeaderSize; result.dataEnd = header.get64(16)
  if result.dataEnd < result.cursor or result.dataEnd > source.size:
    raise newException(ValueError, "invalid STBL v1 data end")
  result.writeState

proc migrateStep*[K, V](m: var StableTableMigration, destination: var IcStableBTreeMap[K, V],
                        maxRecords: Positive): int =
  ## Copies at most `maxRecords` source records.  Replaying duplicate keys is
  ## intentional: the last v1 append record remains the final SBT2 value.
  if m.completed: return 0
  while result < int(maxRecords) and m.cursor < m.dataEnd:
    if m.cursor > m.dataEnd - 8'u64: raise newException(ValueError, "truncated STBL v1 record")
    let lengths = m.source.read(m.cursor, 8)
    var keyLen, valueLen: uint32
    littleEndian32(addr keyLen, unsafeAddr lengths[0]); littleEndian32(addr valueLen, unsafeAddr lengths[4])
    let recordSize = 8'u64 + uint64(keyLen) + uint64(valueLen)
    if recordSize > m.dataEnd - m.cursor: raise newException(ValueError, "invalid STBL v1 record length")
    let keyData = m.source.read(m.cursor + 8'u64, uint64(keyLen))
    let valueData = m.source.read(m.cursor + 8'u64 + uint64(keyLen), uint64(valueLen))
    var keyPos = 0; var valuePos = 0
    destination[deserialize[K](keyData, keyPos)] = deserialize[V](valueData, valuePos)
    m.cursor += recordSize; inc result
  if m.cursor == m.dataEnd: m.completed = true
  m.writeState

proc isComplete*(m: StableTableMigration): bool = m.completed
