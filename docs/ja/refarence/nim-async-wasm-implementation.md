# Nim WASM非同期処理実装方針

このドキュメントは、RustとMotokoの非同期処理実装調査結果に基づき、NimでWASM（特にInternet Computer）向けの非同期処理ライブラリを実装するための設計方針をまとめたものです。

## 1. 概要と目標

### 1.1 実装目標
- **API互換性**: Nim標準`asyncdispatch`と可能な限り同じAPIを提供
- **WASM最適化**: WebAssembly/IC環境に特化した効率的な実装
- **型安全性**: コンパイル時に非同期関連のエラーを検出
- **軽量実装**: Asyncifyに依存しない独自の状態機械実装

### 1.2 対象環境
- **Primary**: Internet Computer (IC) Canister環境（独自ランタイム・wasmtimeベース）
- **Secondary**: WASI (WebAssembly System Interface) 標準環境
- **ビルド環境**: Clang + WASI SDK（Emscripten不使用）
- **実行環境**: スタンドアローンWASM（JSからの呼び出しは不要・Dfinityが提供）

### 1.3 ICPキャニスター環境の特徴と制約
- **独自WASMランタイム**: wasmtimeベースの独自実装でスタンドアローン実行
- **JSブリッジ不要**: DfinityがJS側インターフェースを提供済み
- **メインスレッドアクセス不可**: WASMモジュールとしてICPで実行されるため、メインスレッドへの直接アクセスは不可能
- **メッセージ駆動モデル**: 各処理はメッセージ受信をトリガーとして実行され、処理完了時に自動的にレスポンスが送信される
- **waitFor実装不可**: ブロッキングな待機処理は実装できない（ICPシステムが自動的にメッセージ処理の継続を管理）
- **シングルメッセージ処理**: 一度に1つのメッセージハンドラのみ実行され、awaitによる中断時は他のメッセージ処理に進む

## 2. アーキテクチャ設計

### 2.1 基本型定義

```nim
# src/asyncwasm/types.nim
type
  # 基本Future型（Rustのstd::future::Futureに相当）
  Future[T] = ref object
    value: T                    # 完了時の結果値
    error: ref Exception        # エラー時の例外
    finished: bool              # 完了フラグ
    callbacks: seq[proc()]      # 完了時コールバック
    state: FutureState          # 内部状態
    
  FutureState = enum
    Pending,      # 実行中
    Completed,    # 正常完了
    Failed        # エラー完了
    
  # エグゼキュータ型
  Executor = ref object
    pendingTasks: seq[Future[void]]         # 実行待ちタスク
    waitingIO: Table[AsyncFD, Future[void]] # I/O待ちタスク
    timers: seq[TimerEntry]                 # タイマータスク
    running: bool                           # 実行中フラグ
    
  TimerEntry = object
    deadline: int64           # 満期時刻（UNIX timestamp ms）
    future: Future[void]      # 対応するFuture
    
  AsyncFD = distinct int      # 非同期ファイルディスクリプタ
```

### 2.2 状態機械ベースの実装戦略

RustのFuture実装を参考に、以下の方針で状態機械を構築：

#### 2.2.1 マクロベースのコード変換
```nim
# コンパイル時にasync関数を状態機械に変換
macro async*(prc: untyped): untyped =
  # プロシージャ本体のASTを解析
  # await呼び出し箇所で状態遷移ポイントを識別
  # iterator + closure環境での状態保存コードを生成
  result = generateStateMachine(prc)
```

#### 2.2.2 実行時状態管理
```nim
# 各async関数は内部的にiteratorとして実装
iterator asyncProcIterator(): T =
  var localVar1: SomeType
  var localVar2: AnotherType
  
  # State 0: 初期状態
  localVar1 = someInitialValue()
  
  # State 1: 最初のawait地点
  yield AwaitPoint(someAsyncCall())
  
  # State 2: await後の継続
  localVar2 = processResult(localVar1)
  
  # State N: 完了
  yield FinalResult(localVar2)
```

### 2.3 エグゼキュータ設計

#### 2.3.1 IC特化型エグゼキュータ
Internet Computer環境に最適化されたシングルタスク実行モデル：

```nim
# src/asyncwasm/ic_executor.nim
type
  ICExecutor = ref object of Executor
    messageContext: ICMessageContext    # ICメッセージコンテキスト
    callbackRegistry: Table[CallId, Future[void]]  # inter-canisterコール管理
    
proc executeAsync*(executor: ICExecutor, future: Future[T]) =
  ## ICメッセージハンドラ内でFutureを実行開始（ノンブロッキング）
  ## 完了時はICPシステムが自動的にレスポンスを送信
  executor.currentTask = future
  
  # 初回実行を試行
  if future.finished:
    # 既に完了している場合は即座に結果を返す
    if future.error != nil:
      ic_reply_error(future.error.msg.cstring)
    else:
      ic_reply_success(serialize(future.value))
  else:
    # 未完了の場合は await 処理に任せる
    # ICPシステムがコールバック経由で継続処理を行う
    discard
```

#### 2.3.2 WASI汎用エグゼキュータ（参考実装）
標準WASI環境での汎用的な非同期処理（ICPでは使用しないが参考として記載）：

```nim
# src/asyncwasm/wasi_executor.nim
type
  WASIExecutor = ref object of Executor
    pollSubscriptions: seq[WASIPollSubscription]
    
proc poll*(executor: WASIExecutor, timeout: Duration): int =
  ## WASI poll_oneoffを使用したイベント待機
  ## 注意: ICPキャニスター環境では独自ランタイムを使用
  var subscriptions = executor.pollSubscriptions
  var events: array[32, WASIEvent]
  
  let eventCount = wasiPollOneoff(
    addr subscriptions[0], subscriptions.len,
    addr events[0], events.len
  )
  
  for i in 0..<eventCount:
    case events[i].eventType:
    of WASI_EVENTTYPE_FD_READ:
      resumeIOFuture(executor, events[i].fd, IOEvent.Read)
    of WASI_EVENTTYPE_FD_WRITE:
      resumeIOFuture(executor, events[i].fd, IOEvent.Write)
    of WASI_EVENTTYPE_CLOCK:
      processExpiredTimers(executor)
      
  result = eventCount
```

## 3. コア機能実装

### 3.1 await実装
```nim
# src/asyncwasm/await.nim
template await*[T](future: Future[T]): T =
  ## async関数内でのみ使用可能
  when not declared(currentAsyncContext):
    {.error: "await can only be used inside async procedures".}
  
  if not future.finished:
    # 現在のFutureを一時停止し、待機対象に継続を登録
    registerContinuation(future, currentAsyncContext)
    yield PendingState()
    
  # 完了後の処理
  if future.error != nil:
    raise future.error
  future.value
```

### 3.2 基本非同期関数
```nim
# src/asyncwasm/primitives.nim
proc sleepAsync*(ms: int): Future[void] =
  ## 指定時間後に完了するFuture
  result = newFuture[void]()
  let deadline = getTime().toUnixFloat() * 1000 + ms.float
  getGlobalExecutor().addTimer(deadline, result)

proc spawnAsync*[T](asyncProc: proc(): Future[T]): Future[T] =
  ## 非同期タスクをバックグラウンドで開始
  result = asyncProc()
  getGlobalExecutor().addTask(result)

proc spawnAndForget*[T](future: Future[T]) =
  ## Futureをバックグラウンドで実行（結果を待機しない）
  ## ICPキャニスター環境では結果は自動的にレスポンスとして送信される
  let executor = getGlobalExecutor()
  executor.executeAsync(future)

# 注意: waitFor は ICPキャニスター環境では実装不可
# メインスレッドへのアクセスができないため、ブロッキング待機は不可能
```

### 3.3 I/O操作
```nim
# src/asyncwasm/io.nim
proc readAsync*(fd: AsyncFD, buffer: ptr UncheckedArray[uint8], length: int): Future[int] =
  ## 非同期読み込み
  result = newFuture[int]()
  
  when defined(ic):
    # IC環境では同期I/Oのみサポート
    try:
      let bytesRead = ic_stable_read(fd.int, buffer, length)
      result.complete(bytesRead)
    except:
      result.fail(getCurrentException())
  else:
    # WASI環境での非同期I/O
    getGlobalExecutor().registerIORead(fd, buffer, length, result)

proc writeAsync*(fd: AsyncFD, buffer: ptr UncheckedArray[uint8], length: int): Future[int] =
  ## 非同期書き込み
  result = newFuture[int]()
  
  when defined(ic):
    try:
      let bytesWritten = ic_stable_write(fd.int, buffer, length)
      result.complete(bytesWritten)
    except:
      result.fail(getCurrentException())
  else:
    getGlobalExecutor().registerIOWrite(fd, buffer, length, result)
```

## 4. IC固有機能

### 4.1 Inter-Canister Call
```nim
# src/asyncwasm/ic_calls.nim
proc callAsync*[T](
  canisterId: Principal, 
  methodName: string,
  args: CandidRecord,
  cycles: int64 = 0
): Future[T] =
  ## 他のCanisterの関数を非同期で呼び出し
  result = newFuture[T]()
  
  let callId = ic_call_new(
    canisterId.toBytes(),
    methodName.cstring,
    serializeCandid(args).cstring,
    cycles
  )
  
  # レスポンス待機の登録
  getICExecutor().registerCall(callId, result)
  
  # 呼び出し実行
  ic_call_perform()

proc updateAsync*[T](methodProc: proc(): Future[T]): Future[T] =
  ## Canister updateメソッドの非同期ラッパー
  result = methodProc()
  
  # IC特有の処理（heartbeat等）を考慮した実行
  getICExecutor().executeInMessageContext(result)
```

#### 4.1.1 グローバル変数を使わないコールバック設計

> **アンチパターン:** `var gPendingPublicKey: Future[...]` のように "いま飛んでいるリクエストは 1 つだけ" という前提で **単一の Future をグローバルに保持** する実装は、簡易サンプルとしては動作しますが以下の理由で推奨しません。
> 1. 多重リクエストが来ると上書き・メモリリーク・予期せぬ失敗を引き起こす
> 2. テストでグローバル状態を毎回初期化する必要があり、保守コストが高い
> 3. ライブラリ化した際にスレッド／メッセージ境界をまたぐ安全性が保証できない

代わりに **コールごとに生成した `Future` を `reply_env` / `reject_env` に埋め込む**、または `callId → Future` のテーブルに登録する方式を採用します。
これにより

* 何件リクエストを並列に送っても衝突しない
* `Future` が完了した時点で GC が回収するため後始末が簡単
* セキュリティ面でもグローバル可変状態を露出しない

低レベル API (env にポインタを渡す版) の最小例は以下です。
```nim
proc publicKeyAsync*(arg: EcdsaPublicKeyArgs): Future[EcdsaPublicKeyResult] =
  ## 管理キャニスターの `ecdsa_public_key` を呼び出す非同期ラッパー
  let fut = newFuture[EcdsaPublicKeyResult]("publicKey")
  let ctx = cast[pointer](fut)             # Future への生ポインタを環境に渡す

  ic0_call_new(
    callee_src = 0, callee_size = 0,
    name_src   = cast[int](cstring("ecdsa_public_key")),
    name_size  = 16,
    reply_fun  = cast[int](onReply),
    reply_env  = cast[int](ctx),   # ここに渡す
    reject_fun = cast[int](onReject),
    reject_env = cast[int](ctx)
  )

  let encoded = encodeCandidMessage(@[newCandidRecord(arg)])
  ic0_call_data_append(ptrToInt(addr encoded[0]), encoded.len)
  discard ic0_call_perform()
  return fut

proc onReply(env: uint32) {.exportc.} =
  let fut = cast[Future[EcdsaPublicKeyResult]](env)
  if not fut.finished:
    # 受信データをデコードして完了させる
    let size = ic0_msg_arg_data_size()
    var buf = newSeq[uint8](size)
    ic0_msg_arg_data_copy(ptrToInt(addr buf[0]), 0, size)
    let decoded = decodeCandidMessage(buf)
    let result  = candidValueToEcdsaPublicKeyResult(decoded.values[0])
    complete(fut, result)

proc onReject(env: uint32) {.exportc.} =
  let fut = cast[Future[EcdsaPublicKeyResult]](env)
  if not fut.finished:
    fail(fut, newException(ValueError, "ecdsa_public_key rejected"))
```

上位レベル API (`callAsync`) ではポインタを直接渡さず、`callId` をキーとした `Table[CallId, Future]` に登録しておき、`onReply` 側で `callId` から逆引きして `Future` を完了させる実装でも構いません。これらはいずれも **グローバル変数を使用しない** ことによりスケールと安全性を確保しています。

> **メモ:** 既存のドキュメントに登場するサンプルコードにグローバル変数方式が残っている場合は、順次この方式に置き換えてください。

### 4.2 タイマーとハートビート
```nim
# src/asyncwasm/ic_timers.nim
proc setGlobalTimer*(duration: Duration, callback: proc()) =
  ## ICグローバルタイマーの設定
  let nanoseconds = duration.inNanoseconds()
  ic_global_timer_set(nanoseconds, cast[pointer](callback))

proc heartbeatAsync*(): Future[void] =
  ## ハートビート処理の非同期化
  result = newFuture[void]()
  
  # 定期的にタスクスケジューリングを実行
  proc heartbeatHandler() =
    let executor = getICExecutor()
    executor.processHeartbeat()
    result.complete()
    
  setGlobalTimer(Duration.fromSeconds(1), heartbeatHandler)
```

### 4.3 Clang + WASI SDKビルド環境での実装考慮点

#### 4.3.1 ビルド環境の特徴

NimをWASM向けにコンパイルする際は、**EmscriptenではなくClang + WASI SDK**を使用します。この選択により以下の利点があります：

#### Emscripten vs Clang + WASI SDK
| 項目 | Emscripten | Clang + WASI SDK |
|-----|-----------|-----------------|
| **ビルドチェーン** | 複雑（独自ツールチェーン） | シンプル（標準Clang使用） |
| **非同期実装** | Asyncify依存 | 独自状態機械（軽量） |
| **WASI対応** | エミュレーション | ネイティブサポート |
| **バイナリサイズ** | 大きい | 小さい |
| **パフォーマンス** | オーバーヘッドあり | 最適化済み |

#### 4.3.2 実際のconfig.nims設定

nicp_cdkで生成される`config.nims`の設定例：

```nim
import std/os

# 基本設定
--mm: "orc"                    # ORCメモリ管理（WASMに最適化）
--threads: "off"               # スレッド機能無効化（WASM制約）
--cpu: "wasm32"                # WASM32アーキテクチャ指定
--os: "linux"                  # 基本OSとしてLinux指定
--nomain                       # 自動main関数生成無効化
--cc: "clang"                  # Clangコンパイラ使用（Emscripten不使用）
--define: "useMalloc"          # 標準mallocの使用

# WASI向けターゲット設定
switch("passC", "-target wasm32-wasip1")
switch("passL", "-target wasm32-wasip1")
switch("passL", "-static")           # 静的リンク
switch("passL", "-nostartfiles")     # 標準スタートアップファイル無効
switch("passL", "-Wl,--no-entry")    # エントリーポイント強制無効
switch("passC", "-fno-exceptions")   # 例外処理無効化

# 最適化設定
when defined(release):
  switch("passC", "-Os")       # サイズ最適化
  switch("passC", "-flto")     # リンク時最適化
  switch("passL", "-flto")

# IC特有の設定
let cHeadersPath = "/root/.ic-c-headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)

let icWasiPolyfillPath = getEnv("IC_WASI_POLYFILL_PATH")
switch("passL", "-L" & icWasiPolyfillPath)
switch("passL", "-lic_wasi_polyfill")

let wasiSysroot = getEnv("WASI_SDK_PATH") / "share/wasi-sysroot"
switch("passC", "--sysroot=" & wasiSysroot)
switch("passL", "--sysroot=" & wasiSysroot)
switch("passC", "-I" & wasiSysroot & "/include")

switch("passC", "-D_WASI_EMULATED_SIGNAL")
switch("passL", "-lwasi-emulated-signal")
```

#### 4.3.3 非同期実装への影響

この設定により、非同期処理実装に以下の影響があります：

##### 制約事項
- **`--threads: "off"`**: マルチスレッド非同期は使用不可
- **`-fno-exceptions`**: 標準例外処理が制限される
- **`-nostartfiles`、`--no-entry`**: 独自エントリーポイント必須

##### 利点
- **Emscripten不要**: Asyncifyのオーバーヘッドなし
- **WASI polyfill**: IC環境でのWASI API利用可能
- **ic0 System API**: IC固有機能への直接アクセス
- **静的リンク**: 自己完結型モジュール

#### 4.3.4 実装戦略への反映

```nim
# EmscriptenのAsyncifyを使わない軽量な状態機械実装
type
  AsyncState = enum
    StateInit,     # 初期状態
    StateWaiting,  # await待機中
    StateResumed,  # 再開後
    StateComplete  # 完了

  AsyncContext[T] = ref object
    state: AsyncState
    continuation: proc()  # 継続処理
    result: T
    error: ref Exception
    
# WASI poll_oneoffを直接利用
proc wasiPoll(subscriptions: ptr WASISubscription, 
              events: ptr WASIEvent): int =
  {.importc: "poll_oneoff", header: "wasi/api.h".}

# IC System APIとの統合
proc icSystemCall(method: cstring, args: cstring): cstring =
  {.importc: "ic0_call_simple", header: "ic0.h".}
```

この設計により、EmscriptenのAsyncifyに依存しない、ICPに最適化された軽量な非同期処理ライブラリの実装が可能になります。

## 5. 最適化戦略

### 5.1 コンパイル時最適化
```nim
# マクロでの最適化例
macro optimizeAsync*(body: untyped): untyped =
  # 連続するawaitの結合
  # 不要な状態遷移の除去
  # インライン展開可能な関数の特定
  result = optimizeAsyncAST(body)

# 使用例
proc complexAsyncProc(): Future[int] {.async.} =
  optimizeAsync:
    let a = await simpleCall1()
    let b = await simpleCall2()
    result = a + b
```

### 5.2 メモリ効率化
```nim
# オブジェクトプール使用
type
  FuturePool[T] = object
    available: seq[Future[T]]
    created: int
    
proc borrowFuture*[T](pool: var FuturePool[T]): Future[T] =
  if pool.available.len > 0:
    result = pool.available.pop()
    result.reset()
  else:
    result = Future[T](state: Pending)
    inc pool.created

proc returnFuture*[T](pool: var FuturePool[T], future: Future[T]) =
  pool.available.add(future)
```

### 5.3 コードサイズ最適化
```nim
# テンプレートでの共通コード削減
template commonAsyncSetup*(futureVar: untyped): untyped =
  let executor = getGlobalExecutor()
  futureVar = newFuture[type(futureVar[])]()
  
template commonAsyncCleanup*(futureVar: untyped): untyped =
  if futureVar.error != nil:
    raise futureVar.error
```

## 6. エラー処理とデバッグ

### 6.1 構造化例外処理
```nim
# src/asyncwasm/exceptions.nim
type
  AsyncException* = object of CatchableError
    futureStack*: seq[string]  # 非同期スタックトレース
    
  TimeoutError* = object of AsyncException
  ChannelClosedError* = object of AsyncException
  ICCallError* = object of AsyncException
    callId*: string
    canisterId*: Principal

proc captureAsyncStack(): seq[string] =
  # 現在のasync関数呼び出しスタックを取得
  result = []
  for frame in getCurrentAsyncFrames():
    result.add(frame.procName & ":" & $frame.line)
```

### 6.2 デバッグ支援
```nim
# デバッグモードでの詳細ログ
when defined(asyncDebug):
  template debugAsyncLog*(msg: string) =
    echo "[ASYNC] ", msg, " at ", instantiationInfo()
else:
  template debugAsyncLog*(msg: string) = discard

# パフォーマンス計測
type
  AsyncProfiler* = object
    taskCounts*: Table[string, int]
    totalTimes*: Table[string, float]
    
proc profileAsync*[T](name: string, future: Future[T]): Future[T] =
  when defined(asyncProfile):
    let start = cpuTime()
    result = future
    result.addCallback proc() =
      let elapsed = cpuTime() - start
      getGlobalProfiler().record(name, elapsed)
  else:
    result = future
```

## 7. テスト戦略

### 7.1 単体テスト
```nim
# tests/asyncwasm/test_futures.nim
import unittest
import ../src/asyncwasm

suite "Basic Future Operations":
  test "Future completion":
    proc testProc(): Future[int] {.async.} =
      return 42
      
    # 注意: ICPキャニスター環境ではwaitForは使用不可
    # 代わりにコールバック形式でテスト
    let future = testProc()
    future.addCallback proc() =
      check future.finished
      check future.value == 42
    
  test "Future with await":
    proc asyncAdd(a, b: int): Future[int] {.async.} =
      await sleepAsync(10)  # 10ms待機
      return a + b
      
    # ICPキャニスター環境向けテスト
    let future = asyncAdd(5, 3)
    future.addCallback proc() =
      check future.finished
      check future.value == 8
```

### 7.2 統合テスト
```nim
# tests/asyncwasm/test_ic_integration.nim
proc testICCall(): Future[string] {.async.} =
  let response = await callAsync[string](
    principal("rdmx6-jaaaa-aaaaa-aaadq-cai"),
    "greet",
    %* {"name": "World"}
  )
  return response

when defined(ic):
  suite "IC Integration Tests":
    test "inter-canister call":
      # ICPキャニスター環境向けテスト（waitFor不使用）
      let future = testICCall()
      future.addCallback proc() =
        check future.finished
        check future.value.contains("Hello, World")
```

## 8. ドキュメント化とAPI参考資料

### 8.1 API互換性マップ
| Nim標準asyncdispatch | 本実装 | 備考 |
|-------------------|-------|------|
| `asyncCheck` | `spawnAsync` | タスクのバックグラウンド実行 |
| `waitFor` | **実装不可** | ICPキャニスター環境ではメインスレッドアクセス不可 |
| `sleepAsync` | `sleepAsync` | 完全互換 |
| `asyncdispatch.runForever` | **実装不可** | ICPではメッセージ駆動モデルのため不要 |
| 新規追加 | `spawnAndForget` | ICPでの非同期実行（結果は自動レスポンス送信） |

### 8.2 使用例ドキュメント
```nim
# 基本的な使用例（ICPキャニスター環境向け）
proc example1(): Future[string] {.async.} =
  ## updateメソッドとして使用
  echo "処理開始"
  await sleepAsync(1000)  # 1秒待機
  return "完了"  # 結果は自動的にレスポンスとして送信

# IC固有機能の使用例
proc example2(): Future[void] {.async.} =
  ## queryメソッドとして使用
  let balance = await callAsync[nat](
    ic.managementCanister,
    "canister_status",
    %* {"canister_id": ic.id()}
  )
  echo "Current cycles: ", balance

# エラーハンドリング例
proc example3(): Future[string] {.async.} =
  try:
    let result = await riskyAsyncOperation()
    return result
  except AsyncException as e:
    echo "Async error: ", e.msg
    echo "Stack: ", e.futureStack
    raise

# ICPでのエントリーポイント使用例
{.exportc.}
proc canister_update_process_data(args: cstring): cstring =
  ## ICPエントリーポイント（同期関数）
  let future = example1()  # 非同期処理を開始
  spawnAndForget(future)   # バックグラウンドで実行
  return nil  # 即座に制御を返す（結果は後でレスポンス送信）

# 注意: waitForは使用不可
# let result = waitFor example1()  # ← これはコンパイルエラーになる
```

## 9. 実装ロードマップ

### フェーズ1: 基盤実装 (2週間)
- [ ] 基本型定義 (`Future[T]`, `Executor`)
- [ ] マクロベースの`async`/`await`変換
- [ ] シンプルな同期的エグゼキュータ

### フェーズ2: IC統合 (2週間)
- [ ] IC特化型エグゼキュータ
- [ ] Inter-Canister Call機能
- [ ] IC System API統合

### フェーズ3: 最適化とテスト (1週間)
- [ ] パフォーマンス最適化
- [ ] 包括的テストスイート
- [ ] ドキュメント整備

### フェーズ4: 拡張機能 (1週間)
- [ ] WASI対応
- [ ] 高度なエラーハンドリング
- [ ] プロファイリング機能

## 10. まとめ

本実装方針は、RustとMotokoの調査結果を基に、Nimの言語特性を活かしたWASM向け非同期処理ライブラリの設計を提供します。特に以下の特徴があります：

### 主要な特徴
- **Clang + WASI SDK使用**: EmscriptenのAsyncifyに依存しない軽量実装
- **ICPキャニスター特化**: 独自WASMランタイム（wasmtimeベース）に最適化
- **スタンドアローン実行**: JSブリッジ不要（DfinityがJS側を提供済み）
- **waitFor非対応**: メインスレッドアクセス不可の制約に対応
- **独自状態機械**: コンパイル時最適化による高効率実行

### 実装環境
- **ビルド環境**: Clang + WASI SDK（config.nimsで設定済み）
- **ランタイム環境**: ICPキャニスター独自ランタイム（wasmtimeベース）
- **実行モデル**: スタンドアローンWASM、シングルスレッド、メッセージ駆動

実装完了により、ICPキャニスター環境の独自ランタイムで、EmscriptenやJSブリッジに依存しない、軽量で高効率な非同期プログラミング体験を提供できるようになります。 