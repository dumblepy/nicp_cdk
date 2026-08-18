import std/options

import ./ic0/ic0

type IcEnv* = object

proc contains*(_: type IcEnv, name: string): bool =
  let cName = name.cstring
  ic0_env_var_name_exists(cast[int](cName), name.len) != 0

proc get*(_: type IcEnv, name: string): Option[string] =
  let cName = name.cstring
  let nameSrc = cast[int](cName)

  # env_var_value_size traps when the name does not exist.
  if ic0_env_var_name_exists(nameSrc, name.len) == 0:
    return none(string)

  let size = ic0_env_var_value_size(nameSrc, name.len)
  if size == 0:
    return some("")

  var value = newString(size)
  ic0_env_var_value_copy(nameSrc, name.len, cast[int](addr value[0]), 0, size)
  some(value)

proc getOrDefault*(_: type IcEnv, name: string, defaultValue: string): string =
  IcEnv.get(name).get(defaultValue)

proc names*(_: type IcEnv): seq[string] =
  let count = ic0_env_var_count()
  result = newSeqOfCap[string](count)

  for i in 0..<count:
    let size = ic0_env_var_name_size(i)
    if size == 0:
      result.add("")
      continue

    var name = newString(size)
    ic0_env_var_name_copy(i, cast[int](addr name[0]), 0, size)
    result.add(name)
