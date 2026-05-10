import std/tables
import ../../../../src/nicp_cdk

type PlusOrMinus = enum
  `+`
  `-`


var isInitialized = false
var nameState:string
var symbolState:string
var decimalsState:uint8
var totalSupplyState:Natural = 0
var balancesState:Table[Principal, Natural] = initTable[Principal, Natural]()
var allowancesState:Table[Principal, Table[Principal, Natural]] = initTable[Principal, Table[Principal, Natural]]()



# ==================== private ====================
proc updateBalance(address:Principal, isPlusOrMinus:PlusOrMinus, amount:Natural) =
  if not balancesState.hasKey(address): balancesState[address] = 0
  if isPlusOrMinus == `+`:
    balancesState[address] += amount
  else:
    balancesState[address] -= amount


proc updateAllowance(owner:Principal, spender:Principal, isPlusOrMinus:PlusOrMinus, amount:Natural) =
  if not allowancesState.hasKey(owner): allowancesState[owner] = initTable[Principal, Natural]()
  if not allowancesState[owner].hasKey(spender): allowancesState[owner][spender] = 0

  if isPlusOrMinus == `+`:
    allowancesState[owner][spender] += amount
  else:
    allowancesState[owner][spender] -= amount


# ==================== public ====================
proc constructor(nameArg:string, symbolArg:string, decimalsArg:uint8) =
  if not isInitialized:
    nameState = nameArg
    symbolState = symbolArg
    decimalsState = decimalsArg
    isInitialized = true

proc init() {.update.} =
  constructor("Test", "TST", 18)
  reply()


proc name() {.query.} =
  reply(nameState)


proc symbol() {.query.} =
  reply(symbolState)


proc decimals() {.query.} =
  reply(decimalsState)


proc totalSupply() {.query.} =
  reply(totalSupplyState)


proc mint() {.update.} =
  let caller = Msg.caller()
  let request = Request.new()
  let amount = request.getNat(0)
  updateBalance(caller, `+`, amount)
  totalSupplyState += amount
  reply(true)


proc balanceOf() {.query.} =
  let request = Request.new()
  let owner = request.getPrincipal(0)

  let balance = balancesState.getOrDefault(owner, 0)
  reply(balance.Natural)


proc transfer() {.update.} =
  let caller = Msg.caller()
  let request = Request.new()
  let to = request.getPrincipal(0)
  let amount = request.getNat(1)

  if balancesState.getOrDefault(caller, 0) < amount:
    reply(false)
  else:
    updateBalance(caller, `-`, amount)
    updateBalance(to, `+`, amount)
    reply(true)


proc allowance() {.query.} =
  let request = Request.new()
  let owner = request.getPrincipal(0)
  let spender = request.getPrincipal(1)

  if not allowancesState.hasKey(owner):
    reply(0)
  
  if not allowancesState[owner].hasKey(spender):
    reply(0)
  
  let allowance = allowancesState[owner][spender]
  reply(allowance)


proc approve() {.update.} =
  let caller = Msg.caller()
  let request = Request.new()
  let spender = request.getPrincipal(0)
  let amount = request.getNat(1)

  updateAllowance(caller, spender, `+`, amount)
  reply(true)


proc transferFrom() {.update.} =
  let caller = Msg.caller()
  let request = Request.new()
  let fromAddr = request.getPrincipal(0)
  let toAddr = request.getPrincipal(1)
  let amount = request.getNat(2)


  if balancesState.getOrDefault(fromAddr, 0) < amount:
    reply(false)
  else:
    updateBalance(fromAddr, `-`, amount)
    updateBalance(toAddr, `+`, amount)
    updateAllowance(fromAddr, caller, `-`, amount)
    reply(true)
