## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentLoop — agent 循环本体（task_51 Step 5 §6.3-5）：模型读命令 → 决定调哪个工具 →
## 工具结果回填 → 再决定，直到 final；final 里的任务**一次**交给 TaskApi.Dispatch（一车一帧）。
##
## 状态机：Idle ─Run()─► Requesting ─resp─► Parsing ─┬─ final → Dispatching ─► Done
##                          ▲                        └─ call  → ExecTool ─► 回填 ─┐
##                          └────────── 轮次 +1 ◄───────────────────────────────┘
##
## ⚠️ 三个语义（§6.3-7，写错就是事故）：
##   ① `tasks: []` = 什么都不做，**不是取消**（TaskApi.Dispatch 收到空数组 → 一帧不发）；
##   ② 取消某台车必须显式 `{"vehicle":"X","missions":[]}` —— `mission_count = 0` 是**唯一**取消入口；
##   ③ 一次最多 32 台车、每台车最多 16 条 missions，超了**直接拒**（too_many_tasks），不交给模型解释。
##
## ⚠️ 三个 Godot 坑（§6.3-8）：
##   ① HTTPRequest 一次只能挂一个请求 → HttpTransport 用 _inflight 守（传输层负责）；
##   ② 节点 free 后 request_completed 不再触发，await 会永久挂起 → _Exit_Tree() 里 cancel_request()，
##      传输层每次 await 回来先 is_instance_valid(_http)，本层每个检查点先判 _cancelled；
##   ③ GDScript 没有 try → 传输层与工具层一律返回结构化结果，本层按 ok 分支处理，不靠异常。
##
## ⚠️ 为什么 Run() **不是协程**（与文档伪代码的形态差异，语言限制，非偏好）：
##   Godot 4.7 里协程不能「调用而不 await」——直接调用是 Parse Error，Callable.call() 是运行时
##   `Trying to call an async function without await`；而「_busy 重入」单测必须能在上一个会话
##   进行中发起第二次 Run()。故：Run() 立刻返回 {ok, reason}，推进由 _Drive() 协程完成
##   （Run 里用 call_deferred 起），终态经 `finished(result)` 送出、`Last_Result()` 可取。
##
## ⚠️ 回合回填铁律（§6.3-5-1）：每轮先把模型上一轮的**原始输出逐字**回填成 assistant 消息，
##   再追加 user("工具返回: <json>")。只回填工具结果会让模型看不见自己上一轮的决定、反复调同一个工具。
##   `_Round_Loop` 里 append 的顺序是合同，单测 T2 用 `==` 逐字比较那条 assistant 内容。

class_name AgentLoop
extends Node

## 终态（每次 Run 恰好发一次）
signal finished(result: Dictionary)
## 每轮解析完发一次（诊断用，不接 UI；Step 6 的日志可按它对齐）
signal round_done(round_no: int, action: String)

## ── 四个常量（§6.3-6，值即文档值，唯一真源就在这里）────────────────────────────
const MAX_ROUNDS := 6                      # 轮数上限（模型请求数）
const REQUEST_TIMEOUT_S := 60.0            # 单请求超时（**不复用 llm.gd 的 120**）
const TOTAL_BUDGET_S := 180.0              # 整次会话总预算
const TOOL_RESULT_MAX_CHARS := 800         # 工具结果裁剪阈值

## ── 重试与回填 ────────────────────────────────────────────────────────────────
const RETRY_DELAY_MS := 1000               # 单请求失败重试间隔 1 s
const REMINDER_BAD_JSON := "上一轮输出不是合法 JSON，只输出一个 JSON 对象。"
const TOOL_PREFIX := "工具返回: "
const NOTE_SAME_ARGS := "参数未变，这是上一次的工具结果"
const TRUNCATED_SUFFIX := "…(truncated)"

## ── reason 取值（Run 的返回值 + finished 的载荷都用它）──────────────────────────
const REASON_STARTED := "started"
const REASON_BUSY := "busy"
const REASON_NOT_CONFIGURED := "not_configured"
const REASON_CANCELLED := "cancelled"
const REASON_MAX_ROUNDS := "max_rounds"
const REASON_TIMEOUT := "timeout"
const REASON_REQUEST_FAILED := "request_failed"
const REASON_TOO_MANY := "too_many_tasks"
const REASON_DISPATCH_FAILED := "dispatch_failed"

## ── 状态（State() 的返回值）──────────────────────────────────────────────────
const STATE_IDLE := "idle"
const STATE_REQUESTING := "requesting"
const STATE_PARSING := "parsing"
const STATE_EXEC_TOOL := "exec_tool"
const STATE_DISPATCHING := "dispatching"
const STATE_DONE := "done"

## 兄弟脚本用 preload 常量引用：新文件的 class_name 在首次 --import 之前不在全局类缓存里，
## 直接写裸全局类名会 `Identifier not declared`；preload 常量不受影响。
const AgentTransportScript := preload("res://src/agent/agent_transport.gd")
const AgentParseScript := preload("res://src/agent/agent_parse.gd")
const AgentPromptScript := preload("res://src/agent/agent_prompt.gd")
const AgentToolsScript := preload("res://src/agent/agent_tools.gd")

var _transport = null
var _tools = null
var _registry = null
var _map_data = null
var _place_map = null
var _kernel = null
var _state := STATE_IDLE
var _busy := false
var _cancelled := false
var _messages: Array = []
var _rounds := 0
var _started_ms := 0
var _last_raw := ""
var _last_tasks: Array = []
var _last_results: Array = []
var _last_errors: Array = []
var _last: Dictionary = {}
var _last_sig := ""
var _last_result: Dictionary = {}
var _bad_json_retried := false
var _tool_exec_count := 0
var _tool_log: Array = []
## 生效值（默认 = 上面的常量；Setup 可覆盖，只为让单测能在毫秒级证明两条预算路径）
var _max_rounds := MAX_ROUNDS
var _request_timeout_s := REQUEST_TIMEOUT_S
var _budget_ms := int(TOTAL_BUDGET_S * 1000.0)
var _max_tool_chars := TOOL_RESULT_MAX_CHARS


## 注入依赖（生产与单测同一条路）。deps 键：
##   transport（有 Post / Cancel；缺省 null → _ready 建 HttpTransport(self)）
##   registry / map_data / place_map / kernel（鸭子类型）
##   max_rounds / request_timeout_s / total_budget_s / tool_result_max_chars（可选覆盖）
func Setup(deps: Dictionary) -> Dictionary:
	_registry = deps.get("registry", null)
	_map_data = deps.get("map_data", null)
	_place_map = deps.get("place_map", null)
	_kernel = deps.get("kernel", null)
	_tools = AgentToolsScript.new(_registry, _map_data, _place_map, _kernel)
	_max_rounds = clampi(int(deps.get("max_rounds", MAX_ROUNDS)), 1, 64)
	_request_timeout_s = maxf(0.1, float(deps.get("request_timeout_s", REQUEST_TIMEOUT_S)))
	_budget_ms = maxi(1, int(float(deps.get("total_budget_s", TOTAL_BUDGET_S)) * 1000.0))
	_max_tool_chars = maxi(64, int(deps.get("tool_result_max_chars", TOOL_RESULT_MAX_CHARS)))
	var t: Variant = deps.get("transport", null)
	if t != null and not (t is Object and t.has_method("Post")):
		return {"ok": false, "error": "bad_transport"}
	_transport = t
	return {"ok": true, "error": ""}


## 启动一次会话：**立刻返回**。三种返回：started / busy / not_configured。
## 结果经 finished 信号送出；轮询者用 Is_Busy() + Last_Result()（顺序保证：_last 先写、_busy 后清、再 emit）。
func Run(text: String) -> Dictionary:
	if _busy:
		return {"ok": false, "reason": REASON_BUSY, "rounds": 0}
	if _tools == null:
		return {"ok": false, "reason": REASON_NOT_CONFIGURED, "rounds": 0}
	_busy = true
	_cancelled = false
	_state = STATE_REQUESTING
	_rounds = 0
	_started_ms = Time.get_ticks_msec()
	_last_raw = ""
	_last_tasks = []
	_last_results = []
	_last_errors = []
	_last = {}
	_last_sig = ""
	_last_result = {}
	_bad_json_retried = false
	_tool_exec_count = 0
	_tool_log.clear()
	# 口径 ①：首轮 messages = system + 用户原话，**不含任何运行时事实**（车名 / 坐标 / 在线数）
	_messages = [
		{"role": "system", "content": AgentPromptScript.Build_System()},
		{"role": "user", "content": AgentPromptScript.Build_User(text)},
	]
	# ⚠️ 不能写 `_Drive()`：协程必须 await，这里只能走消息队列
	_Drive.call_deferred()
	return {"ok": true, "reason": REASON_STARTED, "rounds": 0}


## 取消当前会话：置标志 + 传输层 cancel_request()；当前会话会在下一个检查点以
## reason="cancelled" 收尾，且**不会下发任何任务**。Idle 时调用是无害的 no-op。
func Cancel() -> void:
	_cancelled = true
	if _transport != null and _transport is Object and _transport.has_method("Cancel"):
		_transport.Cancel()


func Is_Busy() -> bool:
	return _busy


func State() -> String:
	return _state


func Rounds() -> int:
	return _rounds


## 终态深拷贝（未跑过 → 空字典）
func Last_Result() -> Dictionary:
	return _last.duplicate(true)


## 本次会话的完整 messages（深拷贝；Step 6 取证用）
func Messages() -> Array:
	return _messages.duplicate(true)


## 真正执行过的工具次数（dedupe 命中不计数）——用它断言「同参数只执行一次」
func Tool_Exec_Count() -> int:
	return _tool_exec_count


func Tool_Log() -> Array:
	return _tool_log.duplicate(true)


## 调用方在 Run 之前调：不给 deps.transport 时，_ready 建的是 HttpTransport(self)，端点在这里配
func Set_Endpoint(url: String, api_key: String = "", model: String = "") -> void:
	if _transport == null:
		_transport = AgentTransportScript.HttpTransport.new(self, url, api_key, model, _request_timeout_s)
		return
	if _transport is Object and _transport.has_method("Set_Endpoint"):
		_transport.Set_Endpoint(url, api_key, model)


func _ready() -> void:
	if _transport == null:
		# url 缺省空串 → Post 直接返回 no_endpoint，**不联网**（单测永远注入 FakeTransport）
		_transport = AgentTransportScript.HttpTransport.new(self, "", "", "", _request_timeout_s)


## ⚠️ Godot 坑 ②：节点 free 后 request_completed 不再触发 → 必须在这里 cancel_request()
func _exit_tree() -> void:
	_cancelled = true
	if _transport != null and _transport is Object and _transport.has_method("Cancel"):
		_transport.Cancel()


## 协程：由 Run() 用 call_deferred 起。**任何出口都只发一次 finished**，
## 且顺序固定：_last 先赋值 → _busy = false → emit（轮询者读到的一定是终态）。
func _Drive() -> void:
	var result: Dictionary = await _Round_Loop()
	_state = STATE_DONE
	_last = result
	_busy = false
	finished.emit(_last)


func _Round_Loop() -> Dictionary:
	while true:
		if _cancelled:
			return _Result(false, REASON_CANCELLED)
		if _rounds >= _max_rounds:
			# 轮数**投递前**判：MAX_ROUNDS = 6 恰好允许 6 次请求；用尽时不下发任何任务
			return _Result(false, REASON_MAX_ROUNDS)
		if _Elapsed() > _budget_ms:
			# 总预算耗尽：同样不下发任何任务
			return _Result(false, REASON_TIMEOUT)
		_state = STATE_REQUESTING
		var resp: Dictionary = await _Post_With_Retry()
		if _cancelled:
			return _Result(false, REASON_CANCELLED)
		if not bool(resp.get("ok", false)):
			return _Result(false, REASON_REQUEST_FAILED)
		_rounds += 1
		_state = STATE_PARSING
		var raw := str(resp.get("content", ""))
		_last_raw = raw
		var parsed: Dictionary = AgentParseScript.Parse(raw)
		round_done.emit(_rounds, str(parsed.get("action", "invalid")))
		if not bool(parsed.get("ok", false)):
			var code := str(parsed.get("error", AgentParseScript.ERR_BAD_JSON))
			# 非法 JSON：给第二次机会（回填 assistant 原文 + 格式提醒，**计一轮**，只重试一次）
			if code == AgentParseScript.ERR_BAD_JSON and not _bad_json_retried:
				_bad_json_retried = true
				_messages.append({"role": "assistant", "content": raw})
				_messages.append({"role": "user", "content": REMINDER_BAD_JSON})
				continue
			return _Result(false, code)
		if str(parsed["action"]) == AgentParseScript.ACTION_FINAL:
			_state = STATE_DISPATCHING
			return _Dispatch_Final(parsed["tasks"], raw)
		# ── call：回填铁律 —— 先把模型这一轮的**原始输出逐字**写回 assistant，再写 user(工具返回)
		_state = STATE_EXEC_TOOL
		var payload := _Exec_Tool(str(parsed["tool"]), parsed["args"])
		_messages.append({"role": "assistant", "content": raw})
		_messages.append({"role": "user", "content": TOOL_PREFIX + payload})
	return _Result(false, REASON_MAX_ROUNDS)


## 单请求失败重试 1 次、间隔 1 s、**不额外计轮**（同一 messages 的第二次投递）
func _Post_With_Retry() -> Dictionary:
	if _transport == null:
		return {"ok": false, "content": "", "error": REASON_NOT_CONFIGURED, "elapsed_ms": 0}
	var opt := {"timeout_s": _request_timeout_s}
	var resp: Dictionary = await _transport.Post(_messages, opt)
	if bool(resp.get("ok", false)) or _cancelled:
		return resp
	await _Sleep(RETRY_DELAY_MS)
	if _cancelled:
		return {"ok": false, "content": "", "error": REASON_CANCELLED, "elapsed_ms": 0}
	var again: Dictionary = await _transport.Post(_messages, opt)
	return again


## 返回「已经裁剪过」的 JSON 文本（调用方补 `工具返回: ` 前缀）。
## dedupe：同一 (tool,args) **连续两次**不重复执行（签名 = tool + JSON.stringify(args)，键序无关），
## 回填上次结果并追加 {cached:true, note:"参数未变…"}，防模型死循环。
func _Exec_Tool(tool: String, args: Dictionary) -> String:
	var sig := tool + "|" + JSON.stringify(args)
	if not _last_sig.is_empty() and sig == _last_sig:
		var cached := _last_result.duplicate(true)
		cached["cached"] = true
		cached["note"] = NOTE_SAME_ARGS
		return _Encode(cached)
	_tool_exec_count += 1
	_tool_log.append({"tool": tool, "args": args.duplicate(true)})
	var r: Dictionary = _tools.Exec(tool, args)               # 工具报错不中断，原样回填
	var payload: Dictionary = r.get("result", {})
	_last_sig = sig
	_last_result = payload.duplicate(true)
	return _Encode(payload)


## 工具结果裁剪：JSON 文本 ≤ _max_tool_chars；超了用 {ok, truncated, preview} 包一层，
## **保证仍是合法 JSON**（直接 substr 会把 JSON 切坏，模型就看不懂了）
func _Encode(result: Dictionary) -> String:
	var text := JSON.stringify(result)
	if text.length() <= _max_tool_chars:
		return text
	var keep := text.substr(0, maxi(0, _max_tool_chars - TRUNCATED_SUFFIX.length()))
	while not keep.is_empty():
		var out := JSON.stringify({
			"ok": bool(result.get("ok", false)), "truncated": true,
			"preview": keep + TRUNCATED_SUFFIX,
		})
		if out.length() <= _max_tool_chars:
			return out
		keep = keep.substr(0, maxi(1, int(float(keep.length()) * 0.9)))
	return JSON.stringify({"ok": bool(result.get("ok", false)), "truncated": true})


## final 的下发：**不走 dedupe**（终态动作必须真发帧，否则「先 dispatch_tasks 再 final」会一帧不发）。
## 三语义落点：tasks == [] → TaskApi 什么都不做；missions == [] → 取消帧；
## > 32 台 / > 16 条 → 直接拒（too_many_tasks）、一帧不发、不交给模型解释。
func _Dispatch_Final(tasks: Array, _raw: String) -> Dictionary:
	_last_tasks = tasks.duplicate(true)
	var lim: Dictionary = AgentToolsScript.Check_Tasks_Limits(tasks)
	if not bool(lim["ok"]):
		var code := str(lim["error"])
		_last_errors = [{"vehicle": "", "reason": code}]
		var reason := REASON_TOO_MANY if code == AgentToolsScript.ERR_TOO_MANY_TASKS \
				else AgentParseScript.ERR_BAD_FINAL
		return _Result(false, reason)
	var r: Dictionary = _tools.Exec(AgentToolsScript.TOOL_DISPATCH, {"tasks": tasks})
	var payload: Dictionary = r.get("result", {})
	_last_results = payload.get("sent", [])
	_last_errors = payload.get("errors", [])
	if not bool(payload.get("ok", false)):
		return _Result(false, REASON_DISPATCH_FAILED)
	return _Result(true, "")


## 唯一的终态封装（9 键，顺序稳定；Step 6 的日志直接打印它）
func _Result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok, "reason": reason, "rounds": _rounds, "elapsed_ms": _Elapsed(),
		"last": _last_raw, "tasks": _last_tasks.duplicate(true),
		"results": _last_results.duplicate(true), "errors": _last_errors.duplicate(true),
		"messages": _messages.duplicate(true),
	}


func _Elapsed() -> int:
	return maxi(0, Time.get_ticks_msec() - _started_ms)


## 重试间隔：在树里用计时器（生产），不在树里（单测直调）用阻塞等待，语义等价
func _Sleep(ms: int) -> void:
	var tree = get_tree() if is_inside_tree() else null
	if tree == null:
		OS.delay_msec(ms)
		return
	await tree.create_timer(float(ms) / 1000.0).timeout
