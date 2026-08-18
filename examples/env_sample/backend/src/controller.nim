import std/options
import ../../../../src/nicp_cdk

proc env*() =
  echo "Hello, world!"
  let appEnvOpt = IcEnv.get("APP_ENV")
  let appEnv =
    if appEnvOpt.isSome:
      appEnvOpt.get()
    else:
      "undefined"
  echo "APP_ENV: ", appEnv
  reply(appEnv)
