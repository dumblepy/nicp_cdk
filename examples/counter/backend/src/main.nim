import ../../../../src/nicp_cdk

var counter:uint = 0

proc get() {.query.} =
  reply(counter)

proc set() {.update.} =
  let request = Request.new()
  let value = request.getNat(0)
  counter = value
  reply()

proc inc() {.update.} =
  counter += 1
  reply()
