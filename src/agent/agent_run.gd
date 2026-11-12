extends SceneTree
## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentRun — agent 的 headless CLI（task_51 Step 6 §7.3/§7.4）：三种模式**共用同一条数据通路**
##   --live     真 vLLM + 真 PleiadesKernel（KernelBridge 创建）+ 真 VehicleRegistry + RecordingKernel（**真发帧**）
##   --dry-run  真 vLLM + 真 PleiadesKernel + 真 VehicleRegistry + CaptureKernel（**只记账、不发帧**）
##   --replay <file>  回放 trace 里的 assistant 原文 + CaptureKernel（离线：不发帧、不建 kernel）
##   ⇒ live 与 dry-run 的唯一差别 = `send_command` 是否转发给真 kernel；车、位姿、工具、提示词全同。
##
## 用法（**CWD 必须是 Pictor/**：PleiadesKernel 读的是相对 CWD 的 `.config/config.toml`，
##       理由见 pleiades-base/src/Config/config.rs:83 与 Task/task_41_containment.md:216）：
##   cd Pictor && godot --headless -s src/agent/agent_run.gd -- --dry-run --vehicles 3 "让 simq_ugv_c1 去南门"
##   （--dry-run 也要 world + 3 台 sim 在线：它与 --live 走同一条真通路，只截下行）
##   cd Pictor && godot --headless -s src/agent/agent_run.gd -- --live --vehicles 3 --observe 15 --expect-move 10 "让 simq_ugv_c1 去南门"
##   cd Pictor && godot --headless -s src/agent/agent_run.gd -- --replay /abs/tmp/task51/s6/L2_trace.json
## 退出码：0 成功 / 1 运行失败 / 2 用法错误；末行固定 `[DONE] ok=<bool> reason=<短码> frames=<N>`
##
## ⚠️ 「复用同一条数据通路」的落点（§7.3）：本文件**只 add_child 既有节点**——
##    VehicleRegistry（EventBus.pose_received → 位姿表）、KernelBridge（kernel 信号 → EventBus）、
##    AgentLoop（含 AgentTools → TaskApi → kernel.send_command）。这里**没有**一处
##    `MessageParser.parse_orion_frame`、也没有一处 `OrionMessages.Build_Cmd`：
##    上行全走 KernelBridge、下行全走 TaskApi；本文件只做「组装 + 记账 + 解码取证 + 落 trace」。
##    kernel 只由 KernelBridge 创建（kernel_bridge.gd:16-24），本文件**绝不** ClassDB.instantiate
##    第二个 —— 同机两个 kernel 会抢 listen_port=9123，且第二份随机端口、peer id 相同 → 帧乱。
##
## ⚠️ 为什么 dry-run 也要真 kernel：§7.3 要求"把 PleiadesKernel + KernelBridge + VehicleRegistry + AgentLoop
##    原样挂到 root，每帧 kernel.poll()，等至少 N 台车且每台 has_pose 才 Run()"。因此 dry-run 与 live 一样
##    建 KernelBridge（kernel 由它创建、由它的 _process poll），一样走 EventBus.pose_received → VehicleRegistry；
##    唯一的截断点是下行：注入 AgentLoop 的 `_kernel` 是 CaptureKernel（记帧不转发）。
##    只有 `--replay` 是**离线回放**（不建 kernel、不联网），registry 从被回放 trace 的 `registry` 段重建，
##    缺失时才退回 mock（日志/trace 一律标 mock=true）。
##
## ⚠️ 为什么不用 _process：`extends SceneTree` 的 _process 不被引擎调用（调的是 C++ SceneTree），
##    改用 `_initialize()` 里 `_Main.call_deferred()` + 协程里 `await process_frame` 逐帧推进
##    （与 src/test/test_agent_loop.gd:59 同一手法）。
##
## ⚠️ 为什么每帧再 poll 一次：`PleiadesKernel.poll()` 是 drain 语义
##    （pleiades-terminal/src/lib.rs:167-176），空队列安全；KernelBridge._process 已在 poll，
##    这里显式再 poll 一次只为让「CLI 每帧 poll」可 grep。

const ConfigScript := preload("res://src/agent/agent_config.gd")
const LoopScript := preload("res://src/agent/agent_loop.gd")
const PlaceMapScript := preload("res://src/map/place_map.gd")

## ⚠️ 运行期 load（这三个脚本的 `_ready` / 函数体里直写 autoload 标识符 EventBus，
##    preload 会在**启动期**把它们拉进编译单元 → `Identifier not found`；Step 1 已踩）
const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"
const MAP_SCRIPT := "res://src/renderer_2d/map_data_2d.gd"
const BRIDGE_SCRIPT := "res://src/kernel/kernel_bridge.gd"

## 三种模式（稳定字符串，trace 与日志都按它判）
const MODE_LIVE := "live"
const MODE_DRY := "dry_run"
const MODE_REPLAY := "replay"

## 缺省参数（§7.4 的默认值）
const DEFAULT_TRACE := "user://agent_trace.json"
const DEFAULT_WAIT_S := 30.0
const DEFAULT_BUDGET_S := 240.0
const DEFAULT_VEHICLES := 1
const OBS_STEP_S := 1.0
## 位移机器判据的缺省（-1 = 不判；§7.5-2 的 Pictor 侧证据靠 --expect-move 判）
const DEFAULT_EXPECT_MOVE := 0.0
const DEFAULT_MAX_MOVE := -1.0

## mock 车出生点 = 世界出生点（格 (128,128) 的中心，CoordUtils.tile_to_real → 64.25）
## ⚠️ 只给 --replay 的兜底用（被回放 trace 缺 registry 段时）；live / dry-run 一律真车。
const MOCK_SPAWN := Vector2(64.25, 64.25)

## 退出码（§7.7 / D10）
const EXIT_OK := 0
const EXIT_FAIL := 1
const EXIT_USAGE := 2

## 本文件自己的失败短码（AgentLoop 的 reason 原样透传，不在这里重命名）
const ERR_USAGE := "usage"
const ERR_MODE_CONFLICT := "mode_conflict"
const ERR_CONFIG := "config_error"
const ERR_NODES := "nodes_error"
const ERR_KERNEL_NOT_READY := "kernel_not_ready"
const ERR_WAIT_TIMEOUT := "wait_vehicles_timeout"
const ERR_BUDGET := "cli_budget"
const ERR_RUN := "run_failed"
const ERR_MOTION := "motion_check_failed"


## ─── LlmTransport：一次投递 → 四键 {ok, content, error, elapsed_ms} ───────────────
## 与 agent_transport.gd 的 HttpTransport 逐行同形（同短码、同四键、同 _inflight 守、同
## cancel_request 收尾），**唯一差异** = body 多一个 `chat_template_kwargs` 与 `max_tokens`。
## ⚠️ 为什么不改 agent_transport.gd：Step 6 的硬约束是「只新增、既有文件零改动」（§7.2）。
## ⚠️ 不继承 HttpTransport：内部类 `extends <class_name>` 是对全局类名的引用（依赖类缓存），
##    且 AgentLoop 只按方法名调用（鸭子类型），继承零收益（同 agent_transport.gd:14-17 的结论）。
## ⚠️ 内部类看不到外层脚本的成员：常量/静态方法一律带类名 `AgentTransport.`。
class LlmTransport extends RefCounted:
	var host = null
	var url := ""
	var api_key := ""
	var model := ""
	var max_tokens := 1024
	var timeout_s := AgentTransport.DEFAULT_TIMEOUT_S

	var _http: HTTPRequest = null
	## Godot 坑 ①：HTTPRequest 一次只能挂一个请求 → 自家标志守，不赌版本 API
	var _inflight := false
	var _cancelled := false

	func _init(p_host = null, p_url := "", p_api_key := "", p_model := "",
			p_max_tokens := 1024, p_timeout_s := AgentTransport.DEFAULT_TIMEOUT_S) -> void:
		host = p_host
		url = str(p_url)
		api_key = str(p_api_key)
		model = str(p_model)
		max_tokens = int(p_max_tokens)
		timeout_s = float(p_timeout_s)

	func Set_Endpoint(p_url: String, p_api_key: String = "", p_model: String = "") -> void:
		url = p_url
		api_key = p_api_key
		model = p_model

	## 一次投递。url 为空 → no_endpoint（= 不联网）；任何失败都只走 ok=false + 短码
	func Post(messages: Array, opt: Dictionary = {}) -> Dictionary:
		var t0 := Time.get_ticks_msec()
		if url.strip_edges().is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_NO_ENDPOINT, t0)
		if _cancelled:
			return AgentTransport.Fail(AgentTransport.ERR_CANCELLED, t0)
		if _inflight:
			return AgentTransport.Fail(AgentTransport.ERR_IN_FLIGHT, t0)
		if not _Ensure_Http():
			return AgentTransport.Fail(AgentTransport.ERR_HOST_NOT_IN_TREE, t0)
		_http.timeout = float(opt.get("timeout_s", timeout_s))
		var body := {
			"model": model,
			"messages": messages,
			"stream": false,
			"temperature": 0.0,
			"max_tokens": max_tokens,
			# ⚠️ 唯一差异：vLLM 是思考模型，关掉 thinking 才有纯 JSON
			#    （不带时 content 是「用户要求…」的推理文字 + </think>，解析必失败）
			"chat_template_kwargs": {"enable_thinking": false},
		}
		var headers := PackedStringArray(["Content-Type: application/json"])
		if not api_key.strip_edges().is_empty():
			headers.append("Authorization: Bearer %s" % api_key)
		_inflight = true
		var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			_inflight = false
			return AgentTransport.Fail(AgentTransport.ERR_START_FAILED, t0)
		# Godot 坑 ②：节点 free 后 request_completed 不再触发 → await 会永久挂起
		var resp = await _http.request_completed
		_inflight = false
		if not is_instance_valid(_http):
			return AgentTransport.Fail(AgentTransport.ERR_TRANSPORT_GONE, t0)
		if int(resp[0]) != HTTPRequest.RESULT_SUCCESS:
			return AgentTransport.Fail(AgentTransport.ERR_HTTP_RESULT, t0)
		if int(resp[1]) != 200:
			return AgentTransport.Fail(AgentTransport.ERR_HTTP_STATUS, t0)
		var text: String = (resp[3] as PackedByteArray).get_string_from_utf8()
		# ⚠️ 一律 JSON.new().parse()：JSON.parse_string 失败会往 stderr 打 ERROR
		var json := JSON.new()
		if json.parse(text) != OK or not (json.data is Dictionary):
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var choices: Variant = (json.data as Dictionary).get("choices", [])
		if not (choices is Array) or (choices as Array).is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var message: Variant = (choices[0] as Dictionary).get("message", {})
		if not (message is Dictionary):
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		var content := str((message as Dictionary).get("content", ""))
		if content.strip_edges().is_empty():
			return AgentTransport.Fail(AgentTransport.ERR_BAD_BODY, t0)
		return {
			"ok": true, "content": content, "error": "",
			"elapsed_ms": maxi(0, Time.get_ticks_msec() - t0),
		}

	## 懒建 HTTPRequest（host 不在树里就不建，返回 false → host_not_in_tree）
	func _Ensure_Http() -> bool:
		if is_instance_valid(_http):
			return true
		if host == null or not is_instance_valid(host) or not host.is_inside_tree():
			return false
		_http = HTTPRequest.new()
		_http.name = "AgentRunHttpRequest"
		_http.timeout = timeout_s
		host.add_child(_http)
		return true

	func Cancel() -> void:
		_cancelled = true
		if is_instance_valid(_http) and _inflight:
			_http.cancel_request()

	func Is_In_Flight() -> bool:
		return _inflight


## ─── CaptureKernel：dry-run / replay 的记账壳（**不碰网络**）─────────────────────
## 只实现 TaskApi 用到的那一个方法：send_command(vid, frame) -> bool
class CaptureKernel extends RefCounted:
	## [{vid, frame:PackedByteArray}]，顺序即下发顺序
	var frames: Array = []

	func send_command(id: String, frame: PackedByteArray) -> bool:
		frames.append({"vid": id, "frame": frame})
		return true


## ─── RecordingKernel：live 的记账壳（记账 + **原样转发**给真 kernel）────────────
## 不加任何协议逻辑：帧还是 TaskApi 拼的，发还是 PleiadesKernel 发的
class RecordingKernel extends RefCounted:
	var real = null
	var frames: Array = []

	func _init(p_real = null) -> void:
		real = p_real

	func send_command(id: String, frame: PackedByteArray) -> bool:
		frames.append({"vid": id, "frame": frame})
		if real == null:
			return false
		return bool(real.send_command(id, frame))


## ─── ReplayTransport：把 trace 里的 assistant 原文按序吐出来 ─────────────────────
class ReplayTransport extends RefCounted:
	var contents: Array = []
	var idx := 0

	func _init(p_contents: Array = []) -> void:
		contents = p_contents

	func Post(_messages: Array, _opt: Dictionary = {}) -> Dictionary:
		# 保持协程语义：与真传输一样「投递后让出一帧」，否则整个循环同步跑完
		await Engine.get_main_loop().process_frame
		if idx >= contents.size():
			return {"ok": false, "content": "", "error": "no_more_replays", "elapsed_ms": 0}
		var c := str(contents[idx])
		idx += 1
		return {"ok": true, "content": c, "error": "", "elapsed_ms": 0}

	func Cancel() -> void:
		pass


# ─── 状态 ────────────────────────────────────────────────────
var _mode := ""
var _help := false
var _command := ""
var _replay_path := ""
var _trace_path := DEFAULT_TRACE
var _want_vehicles := DEFAULT_VEHICLES
var _wait_s := DEFAULT_WAIT_S
var _observe_s := 0.0
var _budget_s := DEFAULT_BUDGET_S
var _expect_move := DEFAULT_EXPECT_MOVE
var _max_move := DEFAULT_MAX_MOVE
## 观测窗的首/末位姿快照：vid → {vid,name,x,y,t}（首帧只记一次，末帧每次覆盖）
var _obs_first: Dictionary = {}
var _obs_last: Dictionary = {}

var _cfg: Dictionary = {}
var _registry = null
var _map_data = null
var _place_map = null
var _bridge = null
var _kernel = null
var _transport = null
var _loop = null
var _trace_raw: Dictionary = {}
var _result: Dictionary = {}
var _error := ""


func _initialize() -> void:
	# ⚠️ 这里不 await、不 quit（首帧之后再走，退出更稳）
	_Main.call_deferred()


func _Main() -> void:
	if not _Parse_Args():
		_Usage()
		print("[DONE] ok=false reason=", ERR_USAGE, " frames=0")
		quit(EXIT_USAGE)
		return
	if _help:
		_Usage()
		print("[DONE] ok=true reason=help frames=0")
		quit(EXIT_OK)
		return
	# replay 先读被回放的 trace（命令文本也从里面补），其余模式直接进
	if _mode == MODE_REPLAY:
		_trace_raw = _Read_Trace(_replay_path)
		if _trace_raw.is_empty():
			_error = ERR_USAGE
			print("[FAIL] replay trace 读不出：", _replay_path)
			print("[DONE] ok=false reason=", _error, " frames=0")
			quit(EXIT_FAIL)
			return
		if _command.is_empty():
			_command = str(_trace_raw.get("command", ""))
		# ⚠️ replay 的 trace 不许覆盖被回放的那份（否则第一次跑就把证据写没了）
		if _trace_path == _replay_path:
			_trace_path = "user://agent_trace_replay.json"
	print("[MODE] mode=%s vehicles=%d wait=%.1fs observe=%.1fs budget=%.1fs trace=%s" % [
		_mode, _want_vehicles, _wait_s, _observe_s, _budget_s, _trace_path])
	print("[CMD] ", _command)
	# 读 user://agent_config.cfg（缺文件自动落模板）；失败 → _error=config_error，_Build_Nodes 会拒
	_Load_Config()
	if not _Build_Nodes():
		print("[FAIL] ", _error)
		print("[DONE] ok=false reason=", _error, " frames=0")
		quit(EXIT_FAIL)
		return
	var ok: bool = await _Wait_Ready()
	if ok:
		ok = await _Run()
	_Print_Frames()
	if ok and _observe_s > 0.0:
		await _Observe()
	if ok and (_expect_move > 0.0 or _max_move >= 0.0):
		ok = _Check_Motion()
	_Write_Trace()
	_Print_Summary()
	var frames_n := _Frame_Count()          # 先记：_Teardown 会清掉 _kernel
	_Teardown()
	var reason := str(_result.get("reason", _error))
	if ok:
		reason = "" if reason.is_empty() else reason
	print("[DONE] ok=", ok, " reason=", reason, " frames=", frames_n)
	quit(EXIT_OK if ok else EXIT_FAIL)


# ─── 参数 ────────────────────────────────────────────────────

## `--` 之后的参数（OS.get_cmdline_user_args()）：选项只认一次、重复取后者；
## 其余字符串按出现顺序用**一个空格**拼成命令文本（保留中文与空格）。
func _Parse_Args() -> bool:
	var args := OS.get_cmdline_user_args()
	var words: Array = []
	var i := 0
	while i < args.size():
		var a := str(args[i])
		match a:
			"--live":
				if not _Set_Mode(MODE_LIVE):
					return false
			"--dry-run":
				if not _Set_Mode(MODE_DRY):
					return false
			"--replay":
				if not _Set_Mode(MODE_REPLAY):
					return false
				i += 1
				if i >= args.size():
					print("[FAIL] --replay 缺路径")
					return false
				_replay_path = str(args[i])
			"--vehicles":
				i += 1
				# 0 = 显式关掉门闩（离线只查帧）；负数/非数字按缺省 1
				_want_vehicles = clampi(_As_Int(args, i, DEFAULT_VEHICLES), 0, 16)
			"--expect-move":
				i += 1
				_expect_move = maxf(0.0, _As_Float(args, i, DEFAULT_EXPECT_MOVE))
			"--max-move":
				i += 1
				_max_move = maxf(0.0, _As_Float(args, i, 0.0))
			"--wait":
				i += 1
				_wait_s = maxf(0.0, _As_Float(args, i, DEFAULT_WAIT_S))
			"--observe":
				i += 1
				_observe_s = maxf(0.0, _As_Float(args, i, 0.0))
			"--budget":
				i += 1
				_budget_s = maxf(1.0, _As_Float(args, i, DEFAULT_BUDGET_S))
			"--trace":
				i += 1
				if i >= args.size():
					print("[FAIL] --trace 缺路径")
					return false
				_trace_path = str(args[i])
			"--help", "-h":
				_help = true
			_:
				words.append(a)
		i += 1
	if _help:
		return true
	# 拼命令文本：一个空格连接（保留中文与顺序）
	_command = ""
	for w: Variant in words:
		if not _command.is_empty():
			_command += " "
		_command += str(w)
	if _mode.is_empty():
		print("[FAIL] 缺模式（三选一：--live / --dry-run / --replay <file>）")
		return false
	if _mode != MODE_REPLAY and _command.strip_edges().is_empty():
		print("[FAIL] 缺命令文本")
		return false
	# --expect-move 必须有观察窗，否则永远判 0 位移
	if _expect_move > 0.0 and _observe_s <= 0.0:
		_observe_s = 1.0
		print("[WARN] --expect-move 需要观察窗 → --observe 提为 1.0s")
	return true


## 模式互斥：已设过且不同 → mode_conflict（同给 --live --dry-run ⇒ 退出码 2）
func _Set_Mode(m: String) -> bool:
	if _mode.is_empty() or _mode == m:
		_mode = m
		return true
	_error = ERR_MODE_CONFLICT
	print("[FAIL] mode_conflict: 已有 --%s，又给 --%s（三选一）" % [_mode, m])
	return false


func _As_Int(args: PackedStringArray, i: int, fallback: int) -> int:
	if i >= args.size():
		print("[WARN] 参数缺值，用默认 %d" % fallback)
		return fallback
	var text := str(args[i]).strip_edges()
	if not text.is_valid_int():
		print("[WARN] 不是整数：", text, " → 用默认 ", fallback)
		return fallback
	return int(text)


func _As_Float(args: PackedStringArray, i: int, fallback: float) -> float:
	if i >= args.size():
		print("[WARN] 参数缺值，用默认 %.1f" % fallback)
		return fallback
	var text := str(args[i]).strip_edges()
	if not text.is_valid_float():
		print("[WARN] 不是数字：", text, " → 用默认 ", fallback)
		return fallback
	return float(text)


func _Usage() -> void:
	print("用法（CWD 必须是 Pictor/）：")
	print("  godot --headless -s src/agent/agent_run.gd -- --dry-run [选项] \"<命令>\"")
	print("  godot --headless -s src/agent/agent_run.gd -- --live    [选项] \"<命令>\"")
	print("  godot --headless -s src/agent/agent_run.gd -- --replay <trace.json> [选项]")
	print("选项：--vehicles N（默认 %d）/ --wait S（默认 %.0f）/ --observe S（默认 0）" % [
		DEFAULT_VEHICLES, DEFAULT_WAIT_S])
	print("      --trace <path>（默认 %s）/ --budget S（默认 %.0f）/ --help" % [
		DEFAULT_TRACE, DEFAULT_BUDGET_S])
	print("      --expect-move M（至少一辆车位移 ≥ M，默认关）/ --max-move M（所有车位移 ≤ M，默认关）")
	print("      --vehicles 0 = 显式关掉「等 N 台车」门闩（离线只查帧）")
	print("模式：--dry-run = 真 vLLM + 真 kernel（CaptureKernel **不发帧**）+ 真 N 台车，需 world+sims 在线")
	print("      --live    = 真 vLLM + 真 kernel（**真发帧**）+ 等 N 台真车有位姿（--wait 超时）")
	print("      --replay  = 回放 trace 的 assistant 原文 + CaptureKernel（**不发帧**，离线）")
	print("退出码：0 成功 / 1 运行失败 / 2 用法错误")


# ─── 配置 / 节点 ─────────────────────────────────────────────

## user://agent_config.cfg（缺文件自动落模板）→ 5 键结果；失败时打 [FAIL] 并返回空配置
func _Load_Config() -> Dictionary:
	var acfg = ConfigScript.new()
	var lr: Dictionary = acfg.Load()
	if not bool(lr.get("ok", false)):
		print("[FAIL] agent_config: ", lr.get("error", ""), " path=", lr.get("path", ""))
		_error = ERR_CONFIG
		return {}
	_cfg = lr["config"]
	print("[CFG] created=%s path=%s config=%s" % [
		bool(lr.get("created", false)),
		ProjectSettings.globalize_path(str(lr.get("path", ""))),
		JSON.stringify(_cfg)])
	return _cfg


## 组节点：注册表（真节点）/ 地图（空实例、不进树）/ 地名表 / kernel 侧 / 传输 / AgentLoop
## ⚠️ live 与 dry_run **完全同一条上行通路**（KernelBridge → EventBus → VehicleRegistry），
##    差别只在 `_kernel`：live = RecordingKernel(真 kernel 转发)，dry = CaptureKernel(只记账)。
func _Build_Nodes() -> bool:
	if _cfg.is_empty():
		_error = ERR_CONFIG
		print("[FAIL] agent_config 未加载，无法建节点")
		return false
	# ① 注册表：真 VehicleRegistry（_ready 里连 EventBus 的 4 个信号）
	_registry = (load(REGISTRY_SCRIPT) as Script).new()
	_registry.name = "VehicleRegistry"
	root.add_child(_registry)
	# ② 地图：空 MapData2D 实例，**不进树**（_ready 只连地图信号，本步不验地图；
	#    空图 ⇒ get_cell 返回 0 ⇒ MapApi 判「未知也可通行」，§7 的 A4）
	_map_data = (load(MAP_SCRIPT) as Script).new()
	# ③ 地名表：user://place_map.json（tool/make_place_map.gd 生成）
	_place_map = PlaceMapScript.new("user://place_map.json")
	var pl: Dictionary = _place_map.Load()
	print("[CFG] place_map ok=%s count=%d skipped=%d error=%s path=%s" % [
		bool(pl.get("ok", false)), int(pl.get("count", 0)), int(pl.get("skipped", 0)),
		str(pl.get("error", "")), ProjectSettings.globalize_path("user://place_map.json")])
	# ④ kernel 侧：live / dry_run 都挂真 KernelBridge（kernel 由它创建）
	var real_kernel = null
	if _mode != MODE_REPLAY:
		var b = (load(BRIDGE_SCRIPT) as Script).new()
		b.name = "KernelBridge"
		root.add_child(b)          # → _ready 里 ClassDB.instantiate("PleiadesKernel") + add_child(kernel)
		_bridge = b
		real_kernel = b.kernel
		if real_kernel == null:
			_error = ERR_KERNEL_NOT_READY
			print("[FAIL] PleiadesKernel 未实例化（.gdextension 未加载？见 kernel_bridge.gd:16-18）")
			return false
	if _mode == MODE_LIVE:
		_kernel = RecordingKernel.new(real_kernel)   # 记账 + 原样转发
	elif _mode == MODE_DRY:
		_kernel = CaptureKernel.new()                # 记账，不转发（真 kernel 照旧收包）
	else:
		_kernel = CaptureKernel.new()
		_Seed_From_Trace(_trace_raw)                 # 离线回放：registry 来自 trace
	# ⑤ 传输：replay 走 ReplayTransport，其余走真 vLLM 的 LlmTransport
	if _mode == MODE_REPLAY:
		_transport = ReplayTransport.new(_Trace_Replays())
		print("[CFG] replays=", (_transport.contents as Array).size())
	else:
		_transport = LlmTransport.new(root, str(_cfg["api_url"]), str(_cfg["api_key"]),
			str(_cfg["model"]), int(_cfg["max_tokens"]))
	# ⑥ AgentLoop：**先 Setup（注入 5 个依赖）再 add_child**（_ready 见 _transport 非空就不建 HttpTransport）
	_loop = LoopScript.new()
	_loop.name = "AgentLoop"
	_loop.round_done.connect(_On_Round_Done)
	var sr: Dictionary = _loop.Setup({
		"registry": _registry, "map_data": _map_data, "place_map": _place_map,
		"kernel": _kernel, "transport": _transport,
	})
	if not bool(sr.get("ok", false)):
		_error = ERR_NODES
		print("[FAIL] AgentLoop.Setup: ", sr.get("error", ""))
		return false
	root.add_child(_loop)
	print("[NODES] registry=VehicleRegistry map=MapData2D(空) kernel=%s transport=%s gate=%s vehicles=%d" % [
		_Kernel_Mode_Tag(),
		"ReplayTransport" if _mode == MODE_REPLAY else "LlmTransport",
		"off" if (_mode == MODE_REPLAY or _want_vehicles <= 0) else "on",
		_want_vehicles])
	return true


## replay 的兜底 mock（**只给 --replay**：被回放 trace 缺 registry 段时才用）：
## 走 VehicleRegistry.add_mock_vehicle()，再填出生点位姿（标 mock=true）
func _Seed_Mock_Vehicles(n: int) -> void:
	for i in range(1, n + 1):
		var vid := "mock%02d" % i
		var name := "simq_ugv_c%d" % i
		_registry.add_mock_vehicle(vid, name)
		var rec: Dictionary = _registry.vehicles[vid]
		rec["node_type"] = "car"
		rec["x"] = MOCK_SPAWN.x
		rec["y"] = MOCK_SPAWN.y
		rec["has_pose"] = true
		rec["last_pose_ms"] = Time.get_ticks_msec()
		print("[MOCK] vid=%s name=%s pose=(%.2f, %.2f) mock=true" % [vid, name, MOCK_SPAWN.x, MOCK_SPAWN.y])


## replay 的注册表：先按 trace 的 registry 段重建（同形位姿 ⇒ 同一串帧），缺失则退回 mock
func _Seed_From_Trace(trace: Dictionary) -> void:
	var rows: Variant = trace.get("registry", [])
	if not (rows is Array) or (rows as Array).is_empty():
		print("[MOCK] trace 无 registry 段 → 退回 %d 台 mock" % _want_vehicles)
		_Seed_Mock_Vehicles(_want_vehicles)
		return
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		var r: Dictionary = row
		var vid := str(r.get("vid", ""))
		if vid.is_empty():
			continue
		_registry.add_mock_vehicle(vid, str(r.get("name", "")))
		var rec: Dictionary = _registry.vehicles[vid]
		rec["node_type"] = str(r.get("node_type", "car"))
		rec["x"] = float(r.get("x", 0.0))
		rec["y"] = float(r.get("y", 0.0))
		rec["has_pose"] = bool(r.get("has_pose", true))
		rec["last_pose_ms"] = Time.get_ticks_msec()
		print("[REPLAY] vid=%s name=%s pose=(%.2f, %.2f) mock=true" % [
			vid, str(r.get("name", "")), float(r.get("x", 0.0)), float(r.get("y", 0.0))])
	# 日志里的 vehicles 跟着真实重建的台数走（不是 --vehicles 的缺省 1）
	_want_vehicles = maxi(1, _registry.vehicles.size())


# ─── 门闩 / 主跑 / 观测 ──────────────────────────────────────

## 门闩：等「至少 N 台车、且每台 has_pose == true」或 --wait 超时（§7.3-2）。
## live 与 dry_run **都要过这道门**；replay / --vehicles 0 显式跳过（并打印跳过原因）。
func _Wait_Ready() -> bool:
	if _mode == MODE_REPLAY:
		print("[WAIT] skipped mode=replay（离线回放，无 kernel）")
		return true
	if _want_vehicles <= 0:
		print("[WAIT] skipped vehicles=0（显式关门闩：只查帧，不验链路）")
		return true
	var start := Time.get_ticks_msec()
	var next_report := 0.0
	while true:
		var n := _Pose_Count()
		var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
		if n >= _want_vehicles:
			print("[WAIT] ready: %d 台车均有位姿（elapsed=%.1fs）%s" % [
				n, elapsed, _Node_Type_Breakdown()])
			return true
		if elapsed >= _wait_s:
			_error = ERR_WAIT_TIMEOUT
			print("[FAIL] wait_vehicles_timeout vehicles_with_pose=%d/%d elapsed=%.1fs" % [
				n, _want_vehicles, elapsed])
			print("[WAIT] registry=", JSON.stringify(VehicleApi.Query(_registry, {})))
			return false
		if elapsed >= next_report:
			print("[WAIT] vehicles_with_pose=%d/%d elapsed=%.1fs%s" % [
				n, _want_vehicles, elapsed, _Node_Type_Breakdown()])
			next_report = elapsed + 1.0
		await _Pump_Once()
	return false


## 跑一次会话：轮询 Is_Busy() + Last_Result()（**不** await finished —— 回调里 free 会 Object is locked）
func _Run() -> bool:
	var start := Time.get_ticks_msec()
	var r: Dictionary = _loop.Run(_command)
	if not bool(r.get("ok", false)):
		_error = str(r.get("reason", ERR_RUN))
		print("[FAIL] Run 未启动：", _error)
		return false
	while _loop.Is_Busy():
		if float(Time.get_ticks_msec() - start) > _budget_s * 1000.0:
			_loop.Cancel()
			_error = ERR_BUDGET
			print("[FAIL] cli_budget elapsed=%.1fs" % (float(Time.get_ticks_msec() - start) / 1000.0))
			return false
		await _Pump_Once()
	_result = _loop.Last_Result()
	_Print_Tool_Log()
	if not bool(_result.get("ok", false)):
		_error = str(_result.get("reason", ERR_RUN))
		print("[FAIL] loop reason=", _error, " last=", str(_result.get("last", "")).substr(0, 400))
		return false
	return true


## 每帧一次：显式 poll（KernelBridge._process 已 poll，drain 语义 ⇒ 空队列安全）+ 让出一帧
func _Pump_Once() -> void:
	if _bridge != null and is_instance_valid(_bridge):
		var k = _bridge.kernel
		if k != null:
			k.poll()
	await process_frame


## 只读观测窗口：每 OBS_STEP_S 打一行 [OBS]（§7.5-2 的 Pictor 侧位移证据），
## 并在 t=0 与结束各做一次位姿快照（`_obs_first` / `_obs_last`），供 `[MOTION]` 与 trace 使用。
func _Observe() -> void:
	var start := Time.get_ticks_msec()
	var next := OBS_STEP_S
	print("[OBS] start window=%.1fs（只读）" % _observe_s)
	_Note_Pose_Snapshot(0.0)
	while true:
		var elapsed := float(Time.get_ticks_msec() - start) / 1000.0
		if elapsed >= _observe_s:
			break
		if elapsed >= next:
			_Print_Obs_Row(elapsed)
			_Note_Pose_Snapshot(elapsed)
			next += OBS_STEP_S
		await _Pump_Once()
	var end_t := float(Time.get_ticks_msec() - start) / 1000.0
	_Print_Obs_Row(end_t)
	_Note_Pose_Snapshot(end_t)
	print("[OBS] end elapsed=%.1fs" % end_t)


func _Print_Obs_Row(t: float) -> void:
	var rows := VehicleApi.Query(_registry, {})
	for row: Dictionary in rows:
		print("[OBS] t=%.1fs vid=%s name=%s x=%.2f y=%.2f state=%s pose_age_ms=%d" % [
			t, str(row["vid"]), str(row["name"]), float(row["x"]), float(row["y"]),
			str(row["state"]), int(row["pose_age_ms"])])


## 有位姿的车数（live 门闩的唯一判据）
func _Pose_Count() -> int:
	var n := 0
	if _registry == null or not (_registry is Object):
		return 0
	var vehicles: Variant = _registry.get("vehicles")
	if not (vehicles is Dictionary):
		return 0
	for vid: Variant in (vehicles as Dictionary).keys():
		var rec: Variant = (vehicles as Dictionary)[vid]
		if rec is Dictionary and bool((rec as Dictionary).get("has_pose", false)):
			n += 1
	return n


func _Round_Count() -> int:
	return int(_result.get("rounds", 0))


func _Frame_Count() -> int:
	if _kernel == null or not (_kernel is Object):
		return 0
	var frames: Variant = _kernel.get("frames")
	return (frames as Array).size() if frames is Array else 0


# ─── 打印 / trace ────────────────────────────────────────────

## round_done 直接打印：`[TRACE] round <n> action=<call|final>`（§7.5-1 可 grep 证据）
func _On_Round_Done(round_no: int, action: String) -> void:
	print("[TRACE] round ", round_no, " action=", action)


## 工具日志：`[TOOL] i=<n> tool=<名> args=<json>`（`args` 空字典打印 `{}`）
func _Print_Tool_Log() -> void:
	var i := 0
	for entry: Variant in _loop.Tool_Log():
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		print("[TOOL] i=%d tool=%s args=%s" % [i, str(e.get("tool", "")), JSON.stringify(e.get("args", {}))])
		i += 1


## 帧取证：hex + 解码回 msgid/payload，TASK_SET 再解回 mission_count/missions
## （`type=0` = MISSION_TYPE_GOTO，protocol_def.gd:72）
func _Print_Frames() -> void:
	if _kernel == null or not (_kernel is Object):
		return
	var frames: Variant = _kernel.get("frames")
	if not (frames is Array):
		return
	var i := 0
	for entry: Variant in frames:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		var vid := str(e.get("vid", ""))
		var frame: PackedByteArray = e.get("frame", PackedByteArray())
		print("[FRAME] i=%d vid=%s bytes=%d hex=%s" % [i, vid, frame.size(), frame.hex_encode()])
		var dec: Dictionary = OrionFrame.Decode_Frame(frame)
		if not bool(dec.get("ok", false)):
			print("[FRAME-DECODE] i=%d ok=false error=%s" % [i, str(dec.get("error", ""))])
			i += 1
			continue
		var payload: PackedByteArray = dec["payload"]
		print("[FRAME-DECODE] msgid=%d sysid=%s compid=%d payload_bytes=%d" % [
			int(dec["msgid"]), (dec["sysid"] as PackedByteArray).hex_encode(),
			int(dec["compid"]), payload.size()])
		if int(dec["msgid"]) == ProtocolDef.MSGID_TASK_SET:
			var ts: Dictionary = OrionMessages.Decode_Task_Set(payload)
			print("[TASK_SET] ok=%s mission_count=%d missions=%s" % [
				bool(ts.get("ok", false)), int(ts.get("mission_count", -1)),
				JSON.stringify(ts.get("missions", []))])
		i += 1


func _Print_Summary() -> void:
	print("[SUMMARY] ok=%s reason=%s rounds=%d elapsed_ms=%d tasks=%s results=%s errors=%s" % [
		bool(_result.get("ok", false)), str(_result.get("reason", "")),
		int(_result.get("rounds", 0)), int(_result.get("elapsed_ms", 0)),
		JSON.stringify(_result.get("tasks", [])),
		JSON.stringify(_result.get("results", [])),
		JSON.stringify(_result.get("errors", []))])


## 落 trace（JSON）：mode/mock/kernel_mode/registry_source/command/cwd/config/vehicles/
## observe_s/expect_move/max_move/registry/motion/result/tool_log/replays/frames/error
## ⚠️ `mock` 只在 --replay 为 true；live / dry-run 都是真车（`registry_source=real`）
func _Write_Trace() -> void:
	var data := {
		"mode": _mode,
		"mock": _mode == MODE_REPLAY,
		"kernel_mode": _Kernel_Mode_Tag(),
		"registry_source": ("trace" if _mode == MODE_REPLAY else "real"),
		"command": _command,
		"cwd": ProjectSettings.globalize_path("res://"),
		"config": _cfg,
		"vehicles": _want_vehicles,
		"observe_s": _observe_s,
		"expect_move": _expect_move,
		"max_move": _max_move,
		"registry": VehicleApi.Query(_registry, {}),
		"motion": _Motion_Report(),
		"result": _result,
		"tool_log": _loop.Tool_Log() if _loop != null else [],
		"replays": _Replays_From(_result),
		"frames": _Frames_Hex(),
		"error": _error,
	}
	var f := FileAccess.open(_trace_path, FileAccess.WRITE)
	if f == null:
		print("[FAIL] trace 写入失败：", _trace_path, "（", error_string(FileAccess.get_open_error()), "）")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[TRACE] written: ", ProjectSettings.globalize_path(_trace_path))


func _Frames_Hex() -> Array:
	var out: Array = []
	if _kernel == null or not (_kernel is Object):
		return out
	var frames: Variant = _kernel.get("frames")
	if not (frames is Array):
		return out
	for entry: Variant in frames:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		out.append({
			"vid": str(e.get("vid", "")),
			"bytes": (e.get("frame", PackedByteArray()) as PackedByteArray).size(),
			"hex": (e.get("frame", PackedByteArray()) as PackedByteArray).hex_encode(),
		})
	return out


## trace 的 replays = 本次会话里**模型吐过的每一段原文**（顺序即轮次）。
## ⚠️ 不能只看 result.messages：`final` 那一轮的原文**不在 messages 里**
##    （agent_loop.gd:_Dispatch_Final 直接返回，不回填 assistant），
##    只取 messages 会漏掉最后一轮 → 回放跑到 final 前就没词了（no_more_replays）。
##    故：messages 里的 assistant + 末尾补一条 result.last（final 原文）。
func _Replays_From(result: Dictionary) -> Array:
	var out: Array = []
	var messages: Variant = result.get("messages", [])
	if messages is Array:
		for m: Variant in messages:
			if not (m is Dictionary):
				continue
			if str((m as Dictionary).get("role", "")) == "assistant":
				out.append(str((m as Dictionary).get("content", "")))
	var last := str(result.get("last", ""))
	if not last.strip_edges().is_empty():
		out.append(last)
	return out


## 被回放的 trace 里的原文序列：trace **顶层**就存着上次的 `replays`
## （老 trace / 手写 trace 缺该键时，退回从 `result` 的 messages + last 重算）
func _Trace_Replays() -> Array:
	var rows: Variant = _trace_raw.get("replays", [])
	if rows is Array and not (rows as Array).is_empty():
		var out: Array = []
		for r: Variant in (rows as Array):
			out.append(str(r))
		return out
	return _Replays_From(_trace_raw.get("result", {}))


## 读 trace（JSON）。读不出 / 不是字典 → 空字典（调用方判空，不抛）
func _Read_Trace(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		print("[FAIL] trace 不存在：", path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[FAIL] trace 打不开：", path)
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		print("[FAIL] trace 不是合法 JSON：", path)
		return {}
	return json.data


## ─── 位移取证（机器判据，不靠人眼）──────────────────────────────

## 位姿快照：首帧只记一次，末帧每次覆盖（t=0 也要先记一次，否则"没动"也判不出来）
func _Note_Pose_Snapshot(t: float) -> void:
	var rows := VehicleApi.Query(_registry, {})
	for row: Dictionary in rows:
		var vid := str(row["vid"])
		var rec := {"vid": vid, "name": str(row["name"]),
			"x": float(row["x"]), "y": float(row["y"]), "t": t}
		if not _obs_first.has(vid):
			_obs_first[vid] = rec
		_obs_last[vid] = rec


## 逐车位移表：[{vid,name,x0,y0,x1,y1,dx,dy,moved_m}]（vid 升序，结果可复现）
func _Motion_Report() -> Array:
	var out: Array = []
	var ids: Array = _obs_first.keys()
	ids.sort()
	for vid: Variant in ids:
		var a: Dictionary = _obs_first[vid]
		var b: Variant = _obs_last.get(vid, a)
		var rec: Dictionary = b if b is Dictionary else a
		var p0 := Vector2(float(a["x"]), float(a["y"]))
		var p1 := Vector2(float(rec["x"]), float(rec["y"]))
		out.append({
			"vid": str(vid), "name": str(a["name"]),
			"x0": p0.x, "y0": p0.y, "x1": p1.x, "y1": p1.y,
			"dx": p1.x - p0.x, "dy": p1.y - p0.y,
			"moved_m": p0.distance_to(p1),
		})
	return out


## 位移判据：--expect-move M（至少一辆车位移 ≥ M）/ --max-move M（所有车位移 ≤ M，验"没发帧"/"已停下"）
## 判的是**真位姿**（VehicleRegistry 从 kernel 收上来的 POSE），不是本文件算的。
func _Check_Motion() -> bool:
	var rows := _Motion_Report()
	var worst := 0.0
	for r: Dictionary in rows:
		print("[MOTION] name=%s x0=%.2f y0=%.2f x1=%.2f y1=%.2f dx=%.2f dy=%.2f moved_m=%.2f" % [
			str(r["name"]), float(r["x0"]), float(r["y0"]), float(r["x1"]), float(r["y1"]),
			float(r["dx"]), float(r["dy"]), float(r["moved_m"])])
		worst = maxf(worst, float(r["moved_m"]))
	var good := true
	if _expect_move > 0.0 and worst < _expect_move:
		_error = ERR_MOTION
		good = false
		print("[FAIL] motion expect_move=%.2f 但最大位移 moved_m=%.2f（observe=%.1fs）" % [
			_expect_move, worst, _observe_s])
	if _max_move >= 0.0 and worst > _max_move:
		_error = ERR_MOTION
		good = false
		print("[FAIL] motion max_move=%.2f 但最大位移 moved_m=%.2f（本应静止）" % [
			_max_move, worst])
	if good and not rows.is_empty():
		print("[MOTION] ok=true worst_moved_m=%.2f window=%.1fs" % [worst, _observe_s])
	return good


## trace / 日志用的 kernel 口径标签（评审靠它一眼看出"是不是真链路"）
func _Kernel_Mode_Tag() -> String:
	if _mode == MODE_LIVE:
		return "kernel_bridge+recording"
	if _mode == MODE_DRY:
		return "kernel_bridge+capture"
	return "none+trace"


## registry 里 node_type 的分布（"3 台车"这句话的自证；node_type 来自 peer_info_updated）
func _Node_Type_Breakdown() -> String:
	var counts: Dictionary = {}
	if _registry == null or not (_registry is Object):
		return " node_type={}"
	var vehicles: Variant = _registry.get("vehicles")
	if not (vehicles is Dictionary):
		return " node_type={}"
	for vid: Variant in (vehicles as Dictionary).keys():
		var rec: Variant = (vehicles as Dictionary)[vid]
		if not (rec is Dictionary):
			continue
		var k := str((rec as Dictionary).get("node_type", ""))
		if k.is_empty():
			k = "(空)"
		counts[k] = int(counts.get(k, 0)) + 1
	return " node_type=" + JSON.stringify(counts)


## ─── 收尾 ────────────────────────────────────────────────────
## 主动放掉本文件建的节点/封装，避免 exit 时 ObjectDB / 资源泄漏告警污染取证日志。
## ⚠️ 只 free **本文件创建的**：EventBus 是 autoload（别人的），绝不动。
## ⚠️ 顺序：先 Cancel 传输（可能在飞的请求），再 free 它挂在 root 下的 HTTPRequest，
##    最后 free 节点（AgentLoop._exit_tree 会再 Cancel 一次，幂等）。
func _Teardown() -> void:
	if _transport != null and is_instance_valid(_transport) and _transport.has_method("Cancel"):
		_transport.Cancel()
	var http := root.get_node_or_null("AgentRunHttpRequest")
	if http != null:
		root.remove_child(http)
		http.free()
	for n: Variant in [_loop, _bridge, _registry, _map_data]:
		if n == null or not is_instance_valid(n):
			continue
		if not (n is Node):
			continue
		var node: Node = n
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_loop = null
	_bridge = null
	_registry = null
	_map_data = null
	_kernel = null
	_transport = null
