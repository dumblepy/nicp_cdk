import std/options
import std/asyncfutures
import std/asyncdispatch
import std/tables
import std/strutils
import ../../ic0/ic0
import ../../ic_types/candid_types
import ../../ic_types/ic_principal
import ../../ic_types/ic_record
import ../../ic_types/candid_message/candid_encode
import ../../ic_types/candid_message/candid_decode
import ../../ic_types/candid_message/candid_message_types
import ../../ic_api
import ./estimateGas
import ./management_canister_type


# ================================================================================
# HTTP Outcall related type definitions
# ================================================================================
# Transform関数用の型定義を追加
type
  TransformArgs* = object
    response*: HttpResponsePayload
    context*: seq[byte]  # Blob型（バイトシーケンス）

  HttpHeader* = ref object
    name*: string
    value*: string

  HttpResponsePayload* = object
    status*: uint16
    headers*: seq[HttpHeader]
    body*: seq[byte]


  HttpMethod* {.pure.} = enum
    GET = 0
    POST = 1
    HEAD = 2

  HttpResponse* = object
    status*: uint16
    headers*: seq[HttpHeader]
    body*: seq[byte]

  HttpTransformFunction* = proc(response: HttpResponse): HttpResponse {.nimcall.}

  HttpTransform* = object
    function*: IcFunc
    context*: seq[uint8]

  HttpRequestArgs* = object
    url*: string
    ## IC management canister `http_request` specifies this as `opt nat64`.
    max_response_bytes*: Option[uint64]
    headers*: seq[HttpHeader]
    body*: Option[seq[byte]]
    httpMethod*: HttpMethod
    transform*: Option[HttpTransform]
    is_replicated*: Option[bool]


# ================================================================================
# Transform Functions
# ================================================================================

# proc createDefaultTransform*(): HttpTransform =
#   ## デフォルトのTransform関数: ヘッダーからタイムスタンプを除去
#   proc defaultTransform(response: HttpResponse): HttpResponse =
#     var filteredHeaders: seq[(string, string)] = @[]
#     for header in response.headers:
#       # 一般的な可変ヘッダーを除去
#       let headerNameLower = header[0].toLowerAscii()
#       if headerNameLower notin [
#         "date", "server", "x-request-id", "x-timestamp", 
#         "set-cookie", "expires", "last-modified", "etag",
#         "cache-control", "pragma", "vary", "age",
#         "x-frame-options", "x-content-type-options",
#         "strict-transport-security", "x-xss-protection"
#       ]:
#         filteredHeaders.add(header)
    
#     HttpResponse(
#       status: response.status,
#       headers: filteredHeaders,
#       body: response.body
#     )
  
#   HttpTransform(
#     function: defaultTransform,
#     context: @[]
#   )

# proc createJsonTransform*(): HttpTransform =
#   ## JSON専用Transform関数: JSONフィールドから可変部分を除去
#   proc jsonTransform(response: HttpResponse): HttpResponse =
#     # まずデフォルトTransformを適用
#     let defaultResult = createDefaultTransform().function(response)
    
#     if defaultResult.status != 200:
#       return defaultResult
    
#     try:
#       # レスポンスボディを文字列に変換
#       var jsonStr = ""
#       for b in defaultResult.body:
#         jsonStr.add(char(b))
      
#       # 簡易的なJSON正規化
#       # 一般的な可変JSONフィールドを固定値に置換
#       # 注意: 完全なJSON解析ではなく基本的な文字列置換
      
#       # タイムスタンプフィールドを正規化
#       jsonStr = jsonStr.replace("\"timestamp\":", "\"timestamp\":0,").replace(",0,", ":0,")
      
#       # 日時フィールドを正規化
#       if "\"time\":" in jsonStr:
#         # 簡易的な日時フィールド置換
#         var lines = jsonStr.split("\"time\":")
#         if lines.len > 1:
#           jsonStr = lines[0] & "\"time\":\"normalized\""
#           if lines.len > 2:
#             for i in 2..<lines.len:
#               jsonStr.add("\"time\":\"normalized\"" & lines[i])
      
#       # IDフィールドを正規化
#       if "\"id\":" in jsonStr:
#         # 簡易的なIDフィールド置換
#         var lines = jsonStr.split("\"id\":")
#         if lines.len > 1:
#           jsonStr = lines[0] & "\"id\":\"normalized\""
#           if lines.len > 2:
#             for i in 2..<lines.len:
#               jsonStr.add("\"id\":\"normalized\"" & lines[i])
      
#       # 正規化された文字列をバイトに変換
#       var normalizedBytes: seq[uint8] = @[]
#       for c in jsonStr:
#         normalizedBytes.add(uint8(ord(c)))
      
#       HttpResponse(
#         status: defaultResult.status,
#         headers: defaultResult.headers,
#         body: normalizedBytes
#       )
#     except Exception:
#       # JSON処理でエラーが発生した場合はデフォルトTransformの結果を返す
#       defaultResult
  
#   HttpTransform(
#     function: jsonTransform,
#     context: @[]
#   )


# ================================================================================
# Conversion functions from CandidValue to HTTP Outcall types
# ================================================================================

proc `%`*(request: HttpRequestArgs): CandidRecord =
  ## HttpRequestをCandidRecordに変換（IC Management Canister仕様準拠）
  ## Transformは opt record { function; context } としてエンコードする

  # IC公式仕様：ヘッダーは {name: Text, value: Text} 形式のレコード
  var headersValues: seq[CandidValue] = @[]
  for header in request.headers:
    let headerRecord = %* {
      "name": header.name,
      "value": header.value
    }
    headersValues.add(recordToCandidValue(headerRecord))

  # IC仕様：メソッドはVariant型（小文字ラベル + 空のRecord）
  var methodVariant: CandidRecord
  case request.httpMethod
  of HttpMethod.GET:
    methodVariant = newCVariant("get")
  of HttpMethod.POST:
    methodVariant = newCVariant("post")
  of HttpMethod.HEAD:
    methodVariant = newCVariant("head")

  var fields = initOrderedTable[string, CandidValue]()

  fields["url"] = newCandidText(request.url)

  if request.max_response_bytes.isSome:
    fields["max_response_bytes"] = newCandidOptWithInnerType(
      ctNat64,
      some(newCandidNat64(request.max_response_bytes.get))
    )
  else:
    fields["max_response_bytes"] = newCandidOptWithInnerType(ctNat64, none(CandidValue))

  fields["headers"] = newCandidVec(headersValues)

  if request.body.isSome:
    fields["body"] = newCandidOptWithInnerType(
      ctBlob,
      some(newCandidBlob(request.body.get))
    )
  else:
    fields["body"] = newCandidOptWithInnerType(ctBlob, none(CandidValue))

  fields["method"] = recordToCandidValue(methodVariant)

  if request.transform.isSome:
    let transformValue = request.transform.get
    var transformRecord = CandidRecord(
      kind: ckRecord,
      fields: initOrderedTable[string, CandidValue]()
    )
    transformRecord.fields["function"] = CandidValue(kind: ctFunc, funcVal: transformValue.function)
    transformRecord.fields["context"] = newCandidBlob(transformValue.context)
    fields["transform"] = newCandidOptWithInnerType(
      ctRecord,
      some(newCandidRecord(transformRecord))
    )
  else:
    fields["transform"] = newCandidOptWithInnerType(ctRecord, none(CandidValue))

  if request.is_replicated.isSome:
    fields["is_replicated"] = newCandidOptWithInnerType(
      ctBool,
      some(newCandidBool(request.is_replicated.get))
    )
  else:
    fields["is_replicated"] = newCandidOptWithInnerType(ctBool, some(newCandidBool(false)))

  result = CandidRecord(kind: ckRecord, fields: fields)


proc candidValueToHttpResponse(candidValue: CandidValue): HttpResponse =
  ## Converts a CandidValue to HttpResponse
  if candidValue.kind != ctRecord:
    raise newException(CandidDecodeError, "Expected record type for HttpResponse")

  let recordVal = candidValueToCandidRecord(candidValue)
  let statusRecord = recordVal["status"]
  let statusVal =
    case statusRecord.kind
    of ckNat16:
      statusRecord.getNat16()
    of ckNat:
      statusRecord.getNat().uint16
    else:
      raise newException(CandidDecodeError, "Expected Nat16 status in HttpResponse")
  let headersVal = recordVal["headers"]
  let bodyVal = recordVal["body"].getBlob()

  # Convert headers array to seq[(string, string)]
  var headers: seq[HttpHeader] = @[]
  if headersVal.kind == ckArray:
    for headerItem in headersVal.elems:
      if headerItem.kind == ckRecord:
        if headerItem.fields.hasKey("name") and headerItem.fields.hasKey("value"):
          let nameRecord = candidValueToCandidRecord(headerItem.fields["name"])
          let valueRecord = candidValueToCandidRecord(headerItem.fields["value"])
          headers.add(HttpHeader(name: nameRecord.getStr(), value: valueRecord.getStr()))

  return HttpResponse(
    status: statusVal,
    headers: headers,
    body: bodyVal
  )


# ================================================================================
# HTTP Outcall
# ================================================================================

proc onCallHttpRequestSuccess(env: uint32) {.exportc.} =
  ## Success callback for HTTP Outcall: Restore Future from env and complete it
  let fut = cast[Future[HttpResponse]](env)
  if fut == nil or fut.finished:
    return
  
  try:
    let size = ic0_msg_arg_data_size()
    var buf = newSeq[uint8](size)
    ic0_msg_arg_data_copy(ptrToInt(addr buf[0]), 0, size)
    let decoded = decodeCandidMessage(buf)
    let httpResponse = candidValueToHttpResponse(decoded.values[0])
    devEcho "http_request success status=", httpResponse.status,
            " headers=", httpResponse.headers.len,
            " bodyBytes=", httpResponse.body.len
    complete(fut, httpResponse)
  except Exception as e:
    fail(fut, e)


proc onCallHttpRequestReject(env: uint32) {.exportc.} =
  ## Failure callback for HTTP Outcall: Restore Future from env and fail it
  let fut = cast[Future[HttpResponse]](env)
  if fut == nil or fut.finished:
    return
  # reject コールバック内では ic0_msg_arg_data_size は使用できない
  let msg = "HTTP request call was rejected by the management canister"
  devEcho msg
  fail(fut, newException(ValueError, msg))


const
  # HTTP Outcall: フォールバック推定（サイズベース）の係数
  # - 動的推定（ic0_cost_http_request）が使えない環境向けの保守的な概算
  HttpOutcallFallbackBaseCycles = 5_000_000_000'u64
  HttpOutcallFallbackPerRequestByteCycles = 200_000'u64
  HttpOutcallFallbackPerResponseByteCycles = 20_000'u64

proc calcHttpRequestSize(request: HttpRequestArgs): uint64 =
  var requestSize = request.url.len.uint64
  for header in request.headers:
    requestSize = addCap(requestSize, header.name.len.uint64)
    requestSize = addCap(requestSize, header.value.len.uint64)
  if request.body.isSome:
    requestSize = addCap(requestSize, request.body.get.len.uint64)
  requestSize = addCap(requestSize, ($request.httpMethod).len.uint64)
  if request.transform.isSome:
    requestSize = addCap(requestSize, 100'u64)
  requestSize

proc estimateHttpOutcallCostFallback(request: HttpRequestArgs): uint64 =
  let requestSize = calcHttpRequestSize(request)
  let maxResponseSize = request.max_response_bytes.get(2_000_000'u64)

  var cost = HttpOutcallFallbackBaseCycles
  cost = addCap(cost, mulCap(requestSize, HttpOutcallFallbackPerRequestByteCycles))
  cost = addCap(cost, mulCap(maxResponseSize, HttpOutcallFallbackPerResponseByteCycles))

  let finalCost = addMargin20(cost)
  devEcho "http_outcall fallback cost requestBytes=", requestSize,
          " maxResponseBytes=", maxResponseSize,
          " cost=", cost,
          " finalCost=", finalCost
  finalCost

when defined(release):
  # 動的cycle計算機能（メインネット/テストネット用）
  # コンパイル時フラグ `-d:release` で有効化
  
  proc estimateHttpOutcallCostDynamic(request: HttpRequestArgs): Option[uint64] =
    ## ic0_cost_http_request APIを使用した動的なcycle計算
    try:
      let requestSize = calcHttpRequestSize(request)
      let maxResponseSize = request.max_response_bytes.get(2_000_000'u64)
      
      # IC System APIを使用して正確なコスト計算
      var costBuffer: array[16, uint8]  # 128bit for cycles
      ic0_cost_http_request(requestSize, maxResponseSize, ptrToInt(addr costBuffer[0]))
      
      # 128bitのコスト値をuint64に変換（下位64bitを使用）
      let exactCost = costBufferToUint64(costBuffer)
      
      # 計算結果が0の場合はフォールバック値を使用
      if exactCost == 0:
        devEcho "http_outcall dynamic cost returned 0"
        return none(uint64)
      
      # 20%の安全マージンを追加
      let finalCost = addMargin20(exactCost)
      devEcho "http_outcall dynamic cost exact=", exactCost, " finalCost=", finalCost
      return some(finalCost)
      
    except Exception:
      return none(uint64)

proc estimateHttpOutcallCost(request: HttpRequestArgs): uint64 =
  ## HTTP Outcallのサイクル使用量を計算
  ## 
  ## コンパイル時フラグ `-d:release` を指定すると、
  ## 動的計算を試行します。
  ## デフォルトではフォールバック値を使用します（ローカルレプリカで安全）。
  
  # 動的計算の有効化フラグ（デフォルト: 無効）
  when defined(release):
    # メインネット/テストネット用: 動的計算を試行
    try:
      let dynamicCost = estimateHttpOutcallCostDynamic(request)
      if dynamicCost.isSome:
        devEcho "http_outcall cost using dynamic value=", dynamicCost.get
        return dynamicCost.get
    except Exception:
      # フォールバックへ続行
      discard
  
  # デフォルト: サイズベースのフォールバック推定（ローカルレプリカ対応）
  return estimateHttpOutcallCostFallback(request)


proc httpOutcall*(_:type ManagementCanister, request: HttpRequestArgs): Future[HttpResponse] =
  ## HTTP Outcallをマネジメントキャニスター経由で実行（Rust方式: 自動サイクル送信）
  result = newFuture[HttpResponse]("httpOutcall")

  devEcho "http_outcall request url=", request.url,
          " method=", $request.httpMethod,
          " headers=", request.headers.len,
          " bodyBytes=", (if request.body.isSome: request.body.get.len else: 0),
          " maxResponseBytes=", request.max_response_bytes.get(2_000_000'u64)

  # Management Canisterの呼び出し（t_ecdsa.nimと同じパターン）
  let mgmtPrincipalBytes: seq[uint8] = @[]
  let destPtr = if mgmtPrincipalBytes.len > 0: mgmtPrincipalBytes[0].addr else: nil
  let destLen = mgmtPrincipalBytes.len

  let methodName = "http_request".cstring
  
  ic0_call_new(
    callee_src = cast[int](destPtr),
    callee_size = destLen,
    name_src = cast[int](methodName),
    name_size = methodName.len,
    reply_fun = cast[int](onCallHttpRequestSuccess),
    reply_env = cast[int](result),
    reject_fun = cast[int](onCallHttpRequestReject),
    reject_env = cast[int](result)
  )

  ## 2. Calculate and add required cycles
  # HTTP Outcallに必要なcycle量を計算して追加
  let requiredCycles = estimateHttpOutcallCost(request)
  devEcho "http_outcall cycles=", requiredCycles
  ic0_call_cycles_add128(0, requiredCycles)

  ## 3. Attach argument data and execute
  try:
    let record = %request
    let encoded = encodeCandidMessage(@[recordToCandidValue(record)])
    devEcho "encoded: ", encoded
    var canisterMessage = ""
    for i, v in encoded:
      canisterMessage.add(v.toHex())
    devEcho "canisterMessage: ", canisterMessage

    ic0_call_data_append(ptrToInt(addr encoded[0]), encoded.len)
    let err = ic0_call_perform()
    if err != 0:
      let msg = "call_perform failed with error: " & $err
      fail(result, newException(ValueError, msg))
      return
  except Exception as e:
    fail(result, e)
    return


# ================================================================================
# HTTP Outcall Transform Callbacks
# ================================================================================

# グローバル変数でTransform関数を保持
var registeredTransforms {.threadvar.}: Table[string, HttpTransformFunction]

proc toBytes(s: string): seq[uint8] =
  ## 文字列をバイト配列に変換するヘルパー関数
  result = newSeq[uint8](s.len)
  for i, c in s:
    result[i] = uint8(ord(c))


proc registerTransform*(name: string, transform: HttpTransformFunction) =
  ## Transform関数を登録
  if not registeredTransforms.hasKey("_initialized"):
    registeredTransforms = initTable[string, HttpTransformFunction]()
    registeredTransforms["_initialized"] = nil
  registeredTransforms[name] = transform


proc onTransformCallback(env: uint32) {.exportc.} =
  ## IC System APIから呼び出されるTransform関数コールバック
  try:
    let size = ic0_msg_arg_data_size()
    var buf = newSeq[uint8](size)
    ic0_msg_arg_data_copy(ptrToInt(addr buf[0]), 0, size)
    
    let decoded = decodeCandidMessage(buf)
    if decoded.values.len < 2:
      # エラー: 引数不足
      devEcho "transform callback insufficient args count=", decoded.values.len
      let errorResponse = %* {
        "status": 500'u16,
        "headers": newSeq[CandidRecord](),
        "body": toBytes("Transform function error: insufficient arguments")
      }
      let encoded = encodeCandidMessage(@[recordToCandidValue(errorResponse)])
      ic0_msg_reply_data_append(ptrToInt(addr encoded[0]), encoded.len)
      ic0_msg_reply()
      return
    
    # 第一引数: HttpResponse
    let responseValue = decoded.values[0]
    let httpResponse = candidValueToHttpResponse(responseValue)
    devEcho "transform callback status=", httpResponse.status,
            " headers=", httpResponse.headers.len,
            " bodyBytes=", httpResponse.body.len
    
    # 第二引数: Transform context
    # let contextValue = decoded.values[1]
    # let contextRecord = candidValueToCandidRecord(contextValue)
    # let transformName = contextRecord["function"].getStr()
    
    # 登録されたTransform関数を実行
    var transformedResponse = httpResponse
    
    # 変換されたレスポンスをCandidValueに変換して返す
    var headersArray: seq[CandidRecord] = @[]
    for header in transformedResponse.headers:
      headersArray.add(%* {
        "name": header.name,
        "value": header.value
      })
    
    let resultResponse = %* {
      "status": transformedResponse.status,
      "headers": headersArray,
      "body": transformedResponse.body
    }
    
    let encoded = encodeCandidMessage(@[recordToCandidValue(resultResponse)])
    ic0_msg_reply_data_append(ptrToInt(addr encoded[0]), encoded.len)
    ic0_msg_reply()
    
  except Exception as e:
    # Transform処理でエラーが発生した場合
    devEcho "transform callback error: ", e.msg
    let errorResponse = %* {
      "status": 500'u16,
      "headers": newSeq[CandidRecord](),
      "body": toBytes("Transform function error: " & e.msg)
    }
    let encoded = encodeCandidMessage(@[recordToCandidValue(errorResponse)])
    ic0_msg_reply_data_append(ptrToInt(addr encoded[0]), encoded.len)
    ic0_msg_reply()


# ================================================================================
# Transform Query Functions for IC System API Integration
# ================================================================================

# Transform関数は各キャニスターで個別に実装する必要があります
# この汎用実装は削除し、各キャニスターのmain.nimで実装します

# 初期化時にデフォルトTransform関数を登録
# proc initHttpTransforms*() =
#   ## HTTP Transform機能の初期化
#   registerTransform("default_transform", createDefaultTransform().function)
#   registerTransform("json_transform", createJsonTransform().function)


# ================================================================================
# Response Processing Utility Functions
# ================================================================================

proc getTextBody*(response: HttpResponse): string =
  ## レスポンスボディをテキストとして取得
  result = ""
  for b in response.body:
    result.add(char(b))


proc isSuccess*(response: HttpResponse): bool =
  ## HTTPステータスが成功範囲(200-299)かチェック
  response.status >= 200 and response.status < 300


proc getHeader*(response: HttpResponse, name: string): Option[string] =
  ## 指定されたヘッダー値を取得
  let nameLower = name.toLowerAscii()
  for header in response.headers:
    if header.name.toLowerAscii() == nameLower:
      return some(header.value)
  return none(string)


proc expectJsonResponse*(response: HttpResponse): string =
  ## JSONレスポンスの期待値検証
  if not response.isSuccess():
    raise newException(ValueError, 
      "HTTP request failed with status: " & $response.status)
  
  let contentType = response.getHeader("content-type")
  if contentType.isNone or not contentType.get.contains("application/json"):
    raise newException(ValueError, 
      "Expected JSON response but got: " & contentType.get)
  
  return response.getTextBody()


proc getStatusCode*(response: HttpResponse): int =
  ## HTTPステータスコードをint型で取得
  response.status.int


proc hasHeader*(response: HttpResponse, name: string): bool =
  ## 指定されたヘッダーが存在するかチェック
  response.getHeader(name).isSome


proc getContentLength*(response: HttpResponse): Option[int] =
  ## Content-Lengthヘッダーの値を取得
  let contentLength = response.getHeader("content-length")
  if contentLength.isSome:
    try:
      return some(parseInt(contentLength.get))
    except ValueError:
      return none(int)
  return none(int)


proc isJsonResponse*(response: HttpResponse): bool =
  ## レスポンスがJSON形式かチェック
  let contentType = response.getHeader("content-type")
  if contentType.isSome:
    let ct = contentType.get.toLowerAscii()
    return ct.contains("application/json") or ct.contains("text/json")
  return false


proc getBodySize*(response: HttpResponse): int =
  ## レスポンスボディのサイズを取得
  response.body.len

# ================================================================================
# Convenience HTTP methods
# ================================================================================

# proc httpGet*(
#   _: type ManagementCanister,
#   url: string,
#   headers: seq[(string, string)] = @[],
#   maxResponseBytes: Option[uint64] = none(uint64),
#   transform: Option[HttpTransform] = none(HttpTransform)
# ): Future[HttpResponse] =
#   ## Convenient GET request
#   # let finalTransform = if transform.isSome: transform else: some(createDefaultTransform())
#   let request = HttpRequestArgs(
#     url: url,
#     httpMethod: HttpMethod.GET,
#     headers: headers,
#     body: none(seq[uint8]),
#     max_response_bytes: maxResponseBytes,
#     transform: none(HttpTransform)
#   )
#   return ManagementCanisterhttpOutcall(request)


# proc httpPost*(
#   _: type ManagementCanister,
#   url: string,
#   body: seq[uint8],
#   headers: seq[(string, string)] = @[],
#   maxResponseBytes: Option[uint64] = none(uint64),
#   transform: Option[HttpTransform] = none(HttpTransform)
# ): Future[HttpResponse] =
#   ## Convenient POST request
#   let finalTransform = if transform.isSome: transform else: some(createDefaultTransform())
#   let request = HttpRequestArgs(
#     url: url,
#     httpMethod: HttpMethod.POST,
#     headers: headers,
#     body: some(body),
#     max_response_bytes: maxResponseBytes,
#     transform: finalTransform
#   )
#   return ManagementCanisterhttpOutcall(request)


# proc httpPost*(
#   _: type ManagementCanister,
#   url: string,
#   jsonBody: string,
#   headers: seq[(string, string)] = @[],
#   maxResponseBytes: Option[uint64] = none(uint64),
#   transform: Option[HttpTransform] = none(HttpTransform)
# ): Future[HttpResponse] =
#   ## Convenient POST request with JSON body
#   var requestHeaders = headers
#   requestHeaders.add(("Content-Type", "application/json"))
#   var bodyBytes: seq[uint8] = @[]
#   for c in jsonBody:
#     bodyBytes.add(uint8(ord(c)))
  
#   let finalTransform = if transform.isSome: transform else: some(createJsonTransform())
#   return ManagementCanister.httpPost(url, bodyBytes, requestHeaders, maxResponseBytes, finalTransform)


# proc httpPostJson*(
#   _: type ManagementCanister,
#   url: string,
#   jsonBody: string,
#   headers: seq[(string, string)] = @[],
#   maxResponseBytes: Option[uint64] = none(uint64),
#   idempotencyKey: Option[string] = none(string)
# ): Future[HttpResponse] =
#   ## JSON POST request with Idempotency Key support
#   var requestHeaders = headers
#   requestHeaders.add(("Content-Type", "application/json"))
  
#   # Idempotency Key の設定
#   if idempotencyKey.isSome:
#     requestHeaders.add(("Idempotency-Key", idempotencyKey.get))
#   # TODO: UUIDライブラリが利用可能になったら自動生成を実装
  
#   var bodyBytes: seq[uint8] = @[]
#   for c in jsonBody:
#     bodyBytes.add(uint8(ord(c)))
  
#   return ManagementCanister.httpPost(url, bodyBytes, requestHeaders, maxResponseBytes, some(createJsonTransform()))
