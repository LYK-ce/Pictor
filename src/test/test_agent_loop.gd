extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentLoop 单测（task_51 Step 5 §6.4 / §6.5）
## 用法：godot --headless --path Pictor -s src/test/test_agent_loop.gd
## 期望：末行 `=== ALL PASS: true ===`，退出码 0
## 复现失败：照抄上面这条命令；日志落 tmp/task51/test_agent_loop.log
##
## 覆盖 14 条：文档 §6.4 的 10 条 + 4 条附加
##   T1  final_single_round     单轮直接 final：1 次请求、1 帧、帧内 type/x/y 与 final 一致   §6.4-1
##   T2  two_rounds_backfill    两轮：第 2 次请求含 assistant(raw) + user(工具返回)、工具结果已裁剪 §6.4-2
##   T3  first_user_no_vehicle  首轮 user 只有原话、首请求全部消息无任何 mock 车名（口径 ①）  §6.4-3
##   T4  multi_vehicle_multi    多车多任务：2 帧、字节不同、各 2 条 mission                 §6.4-4
##   T5  max_rounds_no_dispatch 轮数用尽：6 次请求、reason=max_rounds、一帧不发             §6.4-5
##   T6  bad_json_retry         非法 JSON 重试 1 次后成功 / 或 reason=bad_json               §6.4-6
##   T7  tool_error_backfill    工具报错（越界）不中断，第 3 轮仍能 final                    §6.4-7
##   T8  dup_tool_once          同参数连续两次只执行一次（回填 cached + 参数未变）            §6.4-8
##   T9  empty_tasks_vs_cancel  tasks:[] 不发帧；missions:[] 发取消帧（13 B）                §6.4-9
##   T10 busy_reentry           会话进行中再 Run → busy，原会话不受影响                      §6.4-10
##   T11 request_failed_retry   单请求失败重试 1 次（间隔 1 s）/ 两次都失败 → request_failed 〔附加〕
##   T12 tool_result_truncated  超长工具结果截断成 {ok,truncated,preview} 且仍是合法 JSON     〔附加〕
##   T13 resolve_place          PlaceMap.Resolve + MapApi.Check：可站 / adjusted / not_found  〔附加〕
##   T14 total_budget_timeout   总预算耗尽 → reason=timeout、一帧不发                        〔附加〕
##
## 假件：FakeTransport（按脚本吐 replies）+ FakeKernel（记录帧）；注册表用**真 VehicleRegistry**
## （运行期 load()、不进树 → _ready 不跑 → 不碰 EventBus），地图用真 MapData2D，地名表用真 PlaceMap
## （落盘 user://test_agent_place.json，首尾删掉）。**全程无真实网络**：loop 不进树 ⇒ _ready 不跑 ⇒
## 永远不会 new 出生产传输（HTTPRequest 那条路），transport 一律由 Setup 注入 FakeTransport。
##
## ⚠️ 为什么轮询 Is_Busy() + Last_Result()，而不是 `await loop.finished`：
##    在 finished 的回调里 free() 会报 `Object is locked and can't be freed`；轮询返回后再 free 干净。
##
## ⚠️ 用例之间零共享：每个 T 各自 new transport / kernel / registry / loop，结束 free。

const LoopScript := preload("res://src/agent/agent_loop.gd")
const ToolsScript := preload("res://src/agent/agent_tools.gd")
const ParseScript := preload("res://src/agent/agent_parse.gd")
const PromptScript := preload("res://src/agent/agent_prompt.gd")
const PlaceMapScript := preload("res://src/map/place_map.gd")
## 运行期 load：这两个脚本的 _ready 里直写 autoload 标识符 EventBus，preload 会在编译期把
## 它们当依赖一起编译 → `Identifier not found`
const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"
const MAP_SCRIPT := "res://src/renderer_2d/map_data_2d.gd"
const PLACE_PATH := "user://test_agent_place.json"

## 刻意不用「小车A」：SYSTEM 的少样本里有「小车A / 小车1 / 小车2」，
## 用甲 / 乙才能把 T3 的断言做成「首请求的**所有**消息里没有任何 mock 车名」
const VID_A := "aa11"
const VID_B := "bb22"
const NAME_A := "甲车"
const NAME_B := "乙车"

const TOOL_PREFIX := "工具返回: "


## 按脚本吐的假传输：replies 依次弹（String = 原始 content；Dictionary = 整条四键结果）。
## ⚠️ Post 必须是**协程**（await 一帧）：否则整个循环同步跑完，T10 的 _busy 重入观测不到。
class FakeTransport extends RefCounted:
	var replies: Array = []
	var posts: Array = []          # 每次请求的 messages 深拷贝
	var delay_ms := 0
	var cancelled := false

	func Post(messages: Array, _opt: Dictionary = {}) -> Dictionary:
		posts.append(messages.duplicate(true))
		if delay_ms > 0:
			OS.delay_msec(delay_ms)
		await Engine.get_main_loop().process_frame
		if replies.is_empty():
			return {"ok": false, "content": "", "error": "no_replies", "elapsed_ms": 0}
		var r: Variant = replies.pop_front()
		if r is Dictionary:
			return r
		return {"ok": true, "content": str(r), "error": "", "elapsed_ms": 1}

	func Cancel() -> void:
		cancelled = true


## 记录帧的假 kernel（与 test_task_api.gd 同形）
class FakeKernel extends RefCounted:
	var calls: Array = []
	var ret := true

	func send_command(id: String, frame: PackedByteArray) -> bool:
		calls.append({"id": id, "frame": frame})
		return ret


var _registry_script: Script = null
var _map_script: Script = null


func _initialize() -> void:
	_registry_script = load(REGISTRY_SCRIPT) as Script
	_map_script = load(MAP_SCRIPT) as Script
	if _registry_script == null or _map_script == null:
		print("FAIL load 依赖脚本：", REGISTRY_SCRIPT, " / ", MAP_SCRIPT)
		print("=== ALL PASS: false ===")
		quit(1)
		return
	# _initialize 里不直接跑用例（会话里有 await）：交给消息队列，起一条协程跑完全部并 quit
	_Run_All.call_deferred()


## 全部用例串行（T11 有 1 s 重试间隔，故整体约 1~2 s）
func _Run_All() -> void:
	_cleanup()
	var ok := true
	var v1: bool = await _test_final_single_round()
	ok = ok and v1
	var v2: bool = await _test_two_rounds_backfill()
	ok = ok and v2
	var v3: bool = await _test_first_user_no_vehicle_data()
	ok = ok and v3
	var v4: bool = await _test_multi_vehicle_multi_task()
	ok = ok and v4
	var v5: bool = await _test_max_rounds_no_dispatch()
	ok = ok and v5
	var v6: bool = await _test_bad_json_retry()
	ok = ok and v6
	var v7: bool = await _test_tool_error_backfill()
	ok = ok and v7
	var v8: bool = await _test_dup_tool_once()
	ok = ok and v8
	var v9: bool = await _test_empty_tasks_vs_cancel()
	ok = ok and v9
	var v10: bool = await _test_busy_reentry()
	ok = ok and v10
	var v11: bool = await _test_request_failed_retry()
	ok = ok and v11
	var v12: bool = await _test_tool_result_truncated()
	ok = ok and v12
	var v13: bool = await _test_resolve_place()
	ok = ok and v13
	var v14: bool = await _test_total_budget_timeout()
	ok = ok and v14
	_cleanup()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


# ─── 工具 ──────────────────────────────────────────────────────

## 一行断言：失败就打 FAIL（带 tag 与实测值），**不中断后续断言**（一次跑出全部问题）
func _check(acc: bool, cond: bool, tag: String, msg: String) -> bool:
	if cond:
		return acc
	print("FAIL ", tag, ": ", msg)
	return false


func _near(a: float, b: float, eps: float = 1.0e-3) -> bool:
	return absf(a - b) <= eps


## 两辆在线车（真注册表，不进树：_ready 不跑 → 不碰 EventBus）
func _reg_two():
	var reg = _registry_script.new()
	reg.add_mock_vehicle(VID_A, NAME_A)
	reg.add_mock_vehicle(VID_B, NAME_B)
	return reg


## 干净的 AgentLoop：不进树 ⇒ _ready 不跑 ⇒ 不 new HTTPRequest；transport 由测试注入。
## 不声明静态返回类型：在 Node 上取 AgentLoop 的成员会解析失败（同 test_map_api.gd 的教训）
func _loop(tp, reg = null, kern = null, map_data = null, place = null, over: Dictionary = {}):
	var loop = LoopScript.new()
	var deps := {"transport": tp, "registry": reg, "kernel": kern,
			"map_data": map_data, "place_map": place}
	for key: String in over:
		deps[key] = over[key]
	var setup: Dictionary = loop.Setup(deps)
	if not bool(setup["ok"]):
		print("FAIL setup: ", setup)
	return loop


## 起一个会话并等它跑完（轮询，不 await finished —— 见文件头）
func _run(loop, text: String) -> Dictionary:
	var start: Dictionary = loop.Run(text)
	if not bool(start["ok"]):
		return start
	return await _wait(loop)


func _wait(loop) -> Dictionary:
	while loop.Is_Busy():
		await Engine.get_main_loop().process_frame
	return loop.Last_Result()


func _call(tool: String, args: Dictionary) -> String:
	return JSON.stringify({"action": "call", "tool": tool, "args": args})


func _final(tasks: Array) -> String:
	return JSON.stringify({"action": "final", "tasks": tasks})


func _goto(x: float, y: float) -> Dictionary:
	return {"type": "goto", "x": x, "y": y}


## 解一帧 → {ok, msgid, compid, mission_count, missions, error}
func _decode(frame: PackedByteArray) -> Dictionary:
	var f: Dictionary = OrionFrame.Decode_Frame(frame)
	if not bool(f.get("ok", false)):
		return {"ok": false, "error": "frame: " + str(f.get("error", ""))}
	var ts: Dictionary = OrionMessages.Decode_Task_Set(f["payload"])
	if not bool(ts.get("ok", false)):
		return {"ok": false, "error": "task_set: " + str(ts.get("error", ""))}
	return {
		"ok": true, "msgid": int(f["msgid"]), "compid": int(f["compid"]),
		"mission_count": int(ts["mission_count"]), "missions": ts["missions"], "error": "",
	}


## 工具返回消息 → 载荷字典（剥掉 `工具返回: ` 前缀再解析；解析不了给空字典）
func _payload(content: String) -> Dictionary:
	var text := content
	if text.begins_with(TOOL_PREFIX):
		text = text.substr(TOOL_PREFIX.length())
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data


## 一次请求里最后一条工具返回消息（从后往前找 `工具返回: ` 前缀；找不到给空串）。
## 用「找最后一条」而不是写死下标：第 k 次请求的 messages 长度是 2 + 2k，下标容易写错。
func _last_tool(messages: Array) -> String:
	for i in range(messages.size() - 1, -1, -1):
		var m: Variant = messages[i]
		if not (m is Dictionary):
			continue
		var c := str((m as Dictionary).get("content", ""))
		if c.begins_with(TOOL_PREFIX):
			return c
	return ""


func _roles(messages: Array) -> Array:
	var out: Array = []
	for m: Variant in messages:
		if m is Dictionary:
			out.append(str((m as Dictionary).get("role", "")))
		else:
			out.append("")
	return out


func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k


## 空白 chunk：全 0 = log-odds 0 = Unknown；尺寸取协议常量，不写字面量
func _blank_cells() -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(ProtocolDef.CHUNK_SIZE * ProtocolDef.CHUNK_SIZE)
	return cells


func _idx(gx: int, gy: int) -> int:
	return gy * ProtocolDef.CHUNK_SIZE + gx


## 走生产路径上传：set_full（clamp + EventBus.chunk_updated.emit；不进树所以只是普通方法）
func _upload(cells: PackedByteArray):
	var map = _map_script.new()
	map.set_full("test", 0, 0, cells)
	return map


## 删掉测试专用的地名表文件（首尾各一次；不触碰 user://place_map.json）
func _cleanup() -> void:
	for p: String in [PLACE_PATH, PLACE_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			var _err := DirAccess.remove_absolute(p)


# ─── T1 单轮直接 final ────────────────────────────────────────

func _test_final_single_round() -> bool:
	var tag := "T1 final_single_round"
	var ok := true
	# 前置：工具注册表与提示词不许漂（每个工具名都得在 SYSTEM 正文里出现）
	var sys := PromptScript.Build_System()
	for t: String in ToolsScript.TOOL_NAMES:
		ok = _check(ok, sys.contains(t), tag, "SYSTEM 里找不到工具名 " + t)
	var tp := FakeTransport.new()
	tp.replies = [_final([{"vehicle": NAME_A, "missions": [_goto(64.25, 32.75)]}])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "让甲车去 (64.25, 32.75)")
	ok = _check(ok, bool(r.get("ok", false)), tag,
			"ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, int(r.get("rounds", -1)) == 1, tag, "rounds=%s 期望 1" % str(r.get("rounds", -1)))
	ok = _check(ok, tp.posts.size() == 1, tag, "请求数 %d 期望 1" % tp.posts.size())
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	if kern.calls.size() == 1:
		var d: Dictionary = _decode(kern.calls[0]["frame"])
		ok = _check(ok, bool(d["ok"]), tag, "解帧失败：" + str(d.get("error", "")))
		if bool(d["ok"]):
			ok = _check(ok, int(d["msgid"]) == ProtocolDef.MSGID_TASK_SET, tag,
					"msgid=%d 期望 %d" % [int(d["msgid"]), ProtocolDef.MSGID_TASK_SET])
			ok = _check(ok, int(d["compid"]) == ProtocolDef.COMPID_TERMINAL, tag,
					"compid=%d 期望 %d" % [int(d["compid"]), ProtocolDef.COMPID_TERMINAL])
			ok = _check(ok, int(d["mission_count"]) == 1, tag,
					"mission_count=%d 期望 1" % int(d["mission_count"]))
			var ms: Array = d["missions"]
			if ms.size() == 1:
				var m0: Dictionary = ms[0]
				ok = _check(ok, int(m0["type"]) == ProtocolDef.MISSION_TYPE_GOTO, tag,
						"type=%d 期望 %d" % [int(m0["type"]), ProtocolDef.MISSION_TYPE_GOTO])
				ok = _check(ok, _near(float(m0["x"]), 64.25), tag, "x=%f 期望 64.25" % float(m0["x"]))
				ok = _check(ok, _near(float(m0["y"]), 32.75), tag, "y=%f 期望 32.75" % float(m0["y"]))
			else:
				ok = _check(ok, false, tag, "missions 条数 %d 期望 1" % ms.size())
		ok = _check(ok, str(kern.calls[0]["id"]) == VID_A, tag,
				"帧发给了 %s 期望 %s" % [str(kern.calls[0]["id"]), VID_A])
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T2 两轮 + 回填铁律 + 工具结果裁剪 ─────────────────────────

func _test_two_rounds_backfill() -> bool:
	var tag := "T2 two_rounds_backfill"
	var ok := true
	var raw_call := _call("query_vehicles", {"name": NAME_A})
	var raw_final := _final([{"vehicle": NAME_A, "missions": [_goto(64.25, 64.25)]}])
	var tp := FakeTransport.new()
	tp.replies = [raw_call, raw_final]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "让甲车去 (64.25, 64.25)")
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, tp.posts.size() == 2, tag, "请求数 %d 期望 2" % tp.posts.size())
	if tp.posts.size() == 2:
		var second: Array = tp.posts[1]
		ok = _check(ok, second.size() == 4, tag, "第 2 次请求消息数 %d 期望 4" % second.size())
		ok = _check(ok, _roles(second) == ["system", "user", "assistant", "user"], tag,
				"roles=%s 期望 [system,user,assistant,user]" % str(_roles(second)))
		if second.size() == 4:
			# 评审判据 ②：模型上一轮输出**逐字**回填成 assistant（不是 contains，是 ==）
			ok = _check(ok, str(second[2]["content"]) == raw_call, tag,
					"assistant 未逐字回填原始输出")
			var tool_msg := str(second[3]["content"])
			ok = _check(ok, tool_msg.begins_with(TOOL_PREFIX), tag,
					"工具消息缺前缀，实际开头：" + tool_msg.substr(0, 20))
			var pl := _payload(tool_msg)
			var vehicles: Array = pl.get("vehicles", [])
			ok = _check(ok, bool(pl.get("ok", false)) and vehicles.size() == 1, tag,
					"query_vehicles 载荷不对：%s" % str(pl))
			if vehicles.size() == 1:
				# 评审判据 ④：裁剪的正面证据 —— 一条车只回 4 个键
				ok = _check(ok, _sorted_keys(vehicles[0]) == ["name", "state", "x", "y"], tag,
						"vehicle 键=%s 期望 [name,state,x,y]" % str(_sorted_keys(vehicles[0])))
			var summary: Dictionary = pl.get("summary", {})
			ok = _check(ok, _sorted_keys(summary) == ["busy", "cars", "idle", "online", "uavs"], tag,
					"summary 键=%s 期望 [busy,cars,idle,online,uavs]" % str(_sorted_keys(summary)))
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T3 首轮不含任何车辆数据（口径 ① 的实证）────────────────────

func _test_first_user_no_vehicle_data() -> bool:
	var tag := "T3 first_user_no_vehicle_data"
	var ok := true
	# 原话里**刻意不含车名**：否则 T3 的「首请求无 mock 车名」断言会被用户自己说的话绊倒
	var text := "让两台车各去一个地方"
	var tp := FakeTransport.new()
	tp.replies = [_final([{"vehicle": NAME_A, "missions": [_goto(1.25, 2.25)]}])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, text)
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	if tp.posts.is_empty():
		ok = _check(ok, false, tag, "一次请求都没发")
	else:
		var first: Array = tp.posts[0]
		ok = _check(ok, first.size() == 2, tag, "首请求消息数 %d 期望 2（system + user）" % first.size())
		if first.size() == 2:
			ok = _check(ok, str(first[0]["role"]) == "system", tag, "第 1 条不是 system")
			ok = _check(ok, str(first[1]["role"]) == "user", tag, "第 2 条不是 user")
			# 口径 ①：user 消息**逐字**等于用户原话
			ok = _check(ok, str(first[1]["content"]) == text, tag,
					"user 消息被改写了：" + str(first[1]["content"]))
		# 更强的一条：首请求的**所有**消息里都不许出现任何 mock 车名
		for m: Variant in first:
			var content := str((m as Dictionary).get("content", ""))
			ok = _check(ok, not content.contains(NAME_A), tag, "首请求里出现了车名 " + NAME_A)
			ok = _check(ok, not content.contains(NAME_B), tag, "首请求里出现了车名 " + NAME_B)
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T4 多车多任务（一车一帧）───────────────────────────────────

func _test_multi_vehicle_multi_task() -> bool:
	var tag := "T4 multi_vehicle_multi_task"
	var ok := true
	var tp := FakeTransport.new()
	tp.replies = [_final([
		{"vehicle": NAME_A, "missions": [_goto(10.25, 10.25), _goto(11.25, 11.25)]},
		{"vehicle": NAME_B, "missions": [_goto(20.25, 20.25), _goto(21.25, 21.25)]},
	])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "甲乙两车各去两个点")
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.size() == 2, tag, "帧数 %d 期望 2（一车一帧）" % kern.calls.size())
	if kern.calls.size() == 2:
		var f0: PackedByteArray = kern.calls[0]["frame"]
		var f1: PackedByteArray = kern.calls[1]["frame"]
		ok = _check(ok, f0 != f1, tag, "两帧字节相同（多车被塞进同一帧）")
		ok = _check(ok, f0.size() == f1.size(), tag,
				"两帧长度 %d/%d 应相同（各 2 条 goto）" % [f0.size(), f1.size()])
		var d0: Dictionary = _decode(f0)
		var d1: Dictionary = _decode(f1)
		ok = _check(ok, bool(d0["ok"]) and bool(d1["ok"]), tag,
				"解帧失败：" + str(d0.get("error", "")) + str(d1.get("error", "")))
		if bool(d0["ok"]) and bool(d1["ok"]):
			ok = _check(ok, int(d0["mission_count"]) == 2, tag,
					"帧 0 mission_count=%d 期望 2" % int(d0["mission_count"]))
			ok = _check(ok, int(d1["mission_count"]) == 2, tag,
					"帧 1 mission_count=%d 期望 2" % int(d1["mission_count"]))
			ok = _check(ok, str(kern.calls[0]["id"]) == VID_A and str(kern.calls[1]["id"]) == VID_B,
					tag, "帧的 vid 顺序=%s/%s 期望 %s/%s" % [str(kern.calls[0]["id"]),
					str(kern.calls[1]["id"]), VID_A, VID_B])
			var m0: Array = d0["missions"]
			var m1: Array = d1["missions"]
			if m0.size() == 2 and m1.size() == 2:
				# 各车各带自己的点：两帧的两条 x/y 必须互不相同
				ok = _check(ok, not _near(float(m0[0]["x"]), float(m1[0]["x"])), tag,
						"两帧第 1 条 x 相同（%f）" % float(m0[0]["x"]))
				ok = _check(ok, not _near(float(m0[1]["x"]), float(m1[1]["x"])), tag,
						"两帧第 2 条 x 相同（%f）" % float(m0[1]["x"]))
				ok = _check(ok, _near(float(m0[0]["x"]), 10.25) and _near(float(m0[1]["x"]), 11.25),
						tag, "甲车帧的点不是 (10.25, 11.25)")
				ok = _check(ok, _near(float(m1[0]["x"]), 20.25) and _near(float(m1[1]["x"]), 21.25),
						tag, "乙车帧的点不是 (20.25, 21.25)")
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T5 轮数用尽不下发任何任务 ────────────────────────────────

func _test_max_rounds_no_dispatch() -> bool:
	var tag := "T5 max_rounds_no_dispatch"
	var ok := true
	var reply := _call("query_vehicles", {"name": NAME_A})
	var tp := FakeTransport.new()
	tp.replies = [reply, reply, reply, reply, reply, reply, reply, reply]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "一直查车不给结果")
	ok = _check(ok, tp.posts.size() == LoopScript.MAX_ROUNDS, tag,
			"请求数 %d 期望 %d（MAX_ROUNDS）" % [tp.posts.size(), LoopScript.MAX_ROUNDS])
	ok = _check(ok, not bool(r.get("ok", true)), tag, "ok 应为 false")
	ok = _check(ok, str(r.get("reason", "")) == "max_rounds", tag,
			"reason=%s 期望 max_rounds" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.is_empty(), tag, "轮数用尽却发了 %d 帧" % kern.calls.size())
	ok = _check(ok, (r.get("results", []) as Array).is_empty(), tag, "results 应为空")
	ok = _check(ok, (r.get("tasks", []) as Array).is_empty(), tag, "tasks 应为空")
	ok = _check(ok, not str(r.get("last", "")).is_empty(), tag, "last（最后一次输出）应为空")
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T6 非法 JSON 重试 1 次 ───────────────────────────────────

func _test_bad_json_retry() -> bool:
	var tag := "T6 bad_json_retry"
	var ok := true
	# (a) 第一次坏、第二次好：reason 空、rounds==2、assistant 逐字回填坏串 + 一条格式提醒
	var raw_bad := "这不是 JSON"
	var tp := FakeTransport.new()
	tp.replies = [raw_bad, _final([{"vehicle": NAME_A, "missions": [_goto(5.25, 5.25)]}])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "让甲车去 (5.25, 5.25)")
	ok = _check(ok, bool(r.get("ok", false)), tag, "(a) ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, int(r.get("rounds", -1)) == 2, tag, "(a) rounds=%s 期望 2" % str(r.get("rounds", -1)))
	ok = _check(ok, tp.posts.size() == 2, tag, "(a) 请求数 %d 期望 2" % tp.posts.size())
	if tp.posts.size() == 2:
		var second: Array = tp.posts[1]
		ok = _check(ok, second.size() == 4, tag, "(a) 第 2 次请求消息数 %d 期望 4" % second.size())
		if second.size() == 4:
			ok = _check(ok, str(second[2]["content"]) == raw_bad, tag,
					"(a) 非法输出未逐字回填为 assistant")
			ok = _check(ok, str(second[3]["content"]).contains("不是合法 JSON"), tag,
					"(a) 缺格式提醒，实际：" + str(second[3]["content"]))
	loop.free()
	reg.free()
	# (b) 连坏两次：只重试一次 → reason=bad_json、请求数 2、一帧不发
	var tp2 := FakeTransport.new()
	tp2.replies = ["bad", "bad", _final([{"vehicle": NAME_A, "missions": [_goto(5.25, 5.25)]}])]
	var kern2 := FakeKernel.new()
	var reg2 = _reg_two()
	var loop2 = _loop(tp2, reg2, kern2)
	var r2: Dictionary = await _run(loop2, "还是坏 JSON")
	ok = _check(ok, str(r2.get("reason", "")) == "bad_json", tag,
			"(b) reason=%s 期望 bad_json" % str(r2.get("reason", "")))
	ok = _check(ok, tp2.posts.size() == 2, tag, "(b) 请求数 %d 期望 2（只重试一次）" % tp2.posts.size())
	ok = _check(ok, kern2.calls.is_empty(), tag, "(b) 非法 JSON 却发了 %d 帧" % kern2.calls.size())
	loop2.free()
	reg2.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T7 工具报错不中断 ───────────────────────────────────────

func _test_tool_error_backfill() -> bool:
	var tag := "T7 tool_error_backfill"
	var ok := true
	var tp := FakeTransport.new()
	tp.replies = [
		_call("check_passable", {"x": 200, "y": 10}),
		_call("check_passable", {"x": 10, "y": 10}),
		_final([{"vehicle": NAME_A, "missions": [_goto(10.25, 10.25)]}]),
	]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "查两个点再派活")
	ok = _check(ok, tp.posts.size() == 3, tag, "请求数 %d 期望 3（工具报错不该中断）" % tp.posts.size())
	if tp.posts.size() == 3:
		var p1 := _last_tool(tp.posts[1])
		var p2 := _last_tool(tp.posts[2])
		ok = _check(ok, p1.contains("out_of_bounds"), tag, "越界结果没回填，实际：" + p1)
		ok = _check(ok, p1.contains("\"ok\":false"), tag, "越界结果 ok 不是 false，实际：" + p1)
		ok = _check(ok, p2.contains("passable"), tag, "第 2 次工具结果缺 passable，实际：" + p2)
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T8 同参数连续两次只执行一次 ──────────────────────────────

func _test_dup_tool_once() -> bool:
	var tag := "T8 dup_tool_once"
	var ok := true
	var raw := _call("query_vehicles", {"name": NAME_A})
	var tp := FakeTransport.new()
	tp.replies = [raw, raw, _final([{"vehicle": NAME_A, "missions": [_goto(6.25, 6.25)]}])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "重复查同一台车")
	ok = _check(ok, tp.posts.size() == 3, tag, "请求数 %d 期望 3" % tp.posts.size())
	ok = _check(ok, loop.Tool_Exec_Count() == 1, tag,
			"工具执行次数 %d 期望 1（同参数不该重复执行）" % loop.Tool_Exec_Count())
	if tp.posts.size() == 3:
		var p2 := _last_tool(tp.posts[2])
		ok = _check(ok, p2.contains("参数未变"), tag, "第 2 次工具结果缺「参数未变」提示，实际：" + p2)
		var pl := _payload(p2)
		ok = _check(ok, bool(pl.get("cached", false)), tag, "第 2 次工具结果缺 cached:true")
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T9 tasks:[] 不发帧 / missions:[] 发取消帧 ────────────────

func _test_empty_tasks_vs_cancel() -> bool:
	var tag := "T9 empty_tasks_vs_cancel"
	var ok := true
	# (a) tasks: [] = 什么都不做，不是取消
	var tp := FakeTransport.new()
	tp.replies = [_final([])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "什么都不做")
	ok = _check(ok, bool(r.get("ok", false)), tag, "(a) ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.is_empty(), tag,
			"(a) tasks:[] 却发了 %d 帧（空数组不是取消）" % kern.calls.size())
	loop.free()
	reg.free()
	# (b) 显式 missions: [] = 取消帧（mission_count 0，13 B）
	var tp2 := FakeTransport.new()
	tp2.replies = [_final([{"vehicle": NAME_A, "missions": []}])]
	var kern2 := FakeKernel.new()
	var reg2 = _reg_two()
	var loop2 = _loop(tp2, reg2, kern2)
	var r2: Dictionary = await _run(loop2, "取消甲车任务")
	ok = _check(ok, bool(r2.get("ok", false)), tag, "(b) ok 应 true（reason=%s）" % str(r2.get("reason", "")))
	ok = _check(ok, kern2.calls.size() == 1, tag,
			"(b) 取消帧数 %d 期望 1" % kern2.calls.size())
	if kern2.calls.size() == 1:
		var frame: PackedByteArray = kern2.calls[0]["frame"]
		ok = _check(ok, frame.size() == 13, tag, "(b) 取消帧 %d B 期望 13 B" % frame.size())
		var d: Dictionary = _decode(frame)
		ok = _check(ok, bool(d["ok"]), tag, "(b) 解帧失败：" + str(d.get("error", "")))
		if bool(d["ok"]):
			ok = _check(ok, int(d["mission_count"]) == 0, tag,
					"(b) mission_count=%d 期望 0" % int(d["mission_count"]))
	loop2.free()
	reg2.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T10 _busy 重入 ──────────────────────────────────────────

func _test_busy_reentry() -> bool:
	var tag := "T10 busy_reentry"
	var ok := true
	var tp := FakeTransport.new()
	tp.replies = [_final([{"vehicle": NAME_A, "missions": [_goto(7.25, 7.25)]}])]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var s1: Dictionary = loop.Run("第一次")
	ok = _check(ok, bool(s1.get("ok", false)), tag, "第 1 次 Run 应 ok（实际 " + str(s1) + "）")
	var s2: Dictionary = loop.Run("第二次")
	ok = _check(ok, not bool(s2.get("ok", true)), tag, "第 2 次 Run 应被拒（实际 " + str(s2) + "）")
	ok = _check(ok, str(s2.get("reason", "")) == "busy", tag,
			"第 2 次 reason=%s 期望 busy" % str(s2.get("reason", "")))
	var r: Dictionary = await _wait(loop)
	ok = _check(ok, bool(r.get("ok", false)), tag, "原会话应正常完成（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, tp.posts.size() == 1, tag, "请求数 %d 期望 1（第 2 次 Run 不该发请求）" % tp.posts.size())
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T11 单请求失败重试 1 次 ─────────────────────────────────

func _test_request_failed_retry() -> bool:
	var tag := "T11 request_failed_retry"
	var ok := true
	# (a) 第一次失败、第二次成功：重试 1 次，间隔 1 s
	var tp := FakeTransport.new()
	tp.replies = [
		{"ok": false, "content": "", "error": "http_status", "elapsed_ms": 3},
		_final([{"vehicle": NAME_A, "missions": [_goto(8.25, 8.25)]}]),
	]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "先失败再成功")
	ok = _check(ok, tp.posts.size() == 2, tag, "(a) 请求数 %d 期望 2（失败重试一次）" % tp.posts.size())
	ok = _check(ok, bool(r.get("ok", false)), tag, "(a) ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, int(r.get("elapsed_ms", 0)) >= 900, tag,
			"(a) elapsed_ms=%s 期望 >= 900（证明 1 s 重试间隔）" % str(r.get("elapsed_ms", 0)))
	loop.free()
	reg.free()
	# (b) 两次都失败：reason=request_failed、一帧不发
	var tp2 := FakeTransport.new()
	tp2.replies = [
		{"ok": false, "content": "", "error": "http_status", "elapsed_ms": 3},
		{"ok": false, "content": "", "error": "http_status", "elapsed_ms": 3},
	]
	var kern2 := FakeKernel.new()
	var reg2 = _reg_two()
	var loop2 = _loop(tp2, reg2, kern2)
	var r2: Dictionary = await _run(loop2, "两次都失败")
	ok = _check(ok, str(r2.get("reason", "")) == "request_failed", tag,
			"(b) reason=%s 期望 request_failed" % str(r2.get("reason", "")))
	ok = _check(ok, kern2.calls.is_empty(), tag, "(b) 请求失败却发了 %d 帧" % kern2.calls.size())
	loop2.free()
	reg2.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T12 工具结果截断（> 800 字符）────────────────────────────

func _test_tool_result_truncated() -> bool:
	var tag := "T12 tool_result_truncated"
	var ok := true
	var reg = _registry_script.new()
	for i in range(40):
		reg.add_mock_vehicle("v%02d" % i, "车%02d" % i)
	var tp := FakeTransport.new()
	tp.replies = [
		_call("query_vehicles", {}),
		_final([{"vehicle": "车00", "missions": [_goto(9.25, 9.25)]}]),
	]
	var kern := FakeKernel.new()
	var loop = _loop(tp, reg, kern)
	var r: Dictionary = await _run(loop, "看看有哪些车")
	ok = _check(ok, tp.posts.size() == 2, tag, "请求数 %d 期望 2" % tp.posts.size())
	if tp.posts.size() == 2:
		var content := str(tp.posts[1][3]["content"])
		ok = _check(ok, content.begins_with(TOOL_PREFIX), tag, "工具消息缺前缀")
		var text := content
		if text.begins_with(TOOL_PREFIX):
			text = text.substr(TOOL_PREFIX.length())
		ok = _check(ok, text.length() <= 800, tag, "工具结果 %d 字符，超过 800" % text.length())
		ok = _check(ok, text.contains("…(truncated)"), tag, "截断结果缺 (truncated) 标记")
		var json := JSON.new()
		ok = _check(ok, json.parse(text) == OK, tag, "截断后不是合法 JSON：" + text.substr(0, 60))
		if json.parse(text) == OK and json.data is Dictionary:
			ok = _check(ok, _sorted_keys(json.data) == ["ok", "preview", "truncated"], tag,
					"截断信封键=%s 期望 [ok,preview,truncated]" % str(_sorted_keys(json.data)))
			ok = _check(ok, bool((json.data as Dictionary).get("truncated", false)), tag,
					"truncated 不是 true")
	ok = _check(ok, bool(r.get("ok", false)), tag,
			"超长结果不该中断循环（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T13 resolve_place：可站 / adjusted / not_found ───────────

func _test_resolve_place() -> bool:
	var tag := "T13 resolve_place"
	var ok := true
	# 地图：格 (64,64) Occupied，其正北 (64,63) Free，其余 Unknown
	var cells := _blank_cells()
	cells[_idx(64, 64)] = ChunkData2D.to_u8(ProtocolDef.LOG_ODDS_CLAMP)
	cells[_idx(64, 63)] = ChunkData2D.to_u8(-ProtocolDef.LOG_ODDS_CLAMP)
	var map = _upload(cells)
	# 地名表：南门落在 Unknown 格（可站）、北墙落在 Occupied 格（要换点）
	var pm = PlaceMapScript.new(PLACE_PATH)
	var _lr: Dictionary = pm.Load()
	var s1: Dictionary = pm.Set({"id": "south_gate", "name": "南门", "gx": 128, "gy": 128})
	ok = _check(ok, bool(s1["ok"]), tag, "PlaceMap.Set(南门) 失败：" + str(s1.get("error", "")))
	var s2: Dictionary = pm.Set({"id": "north_wall", "name": "北墙", "gx": 64, "gy": 64})
	ok = _check(ok, bool(s2["ok"]), tag, "PlaceMap.Set(北墙) 失败：" + str(s2.get("error", "")))
	var tp := FakeTransport.new()
	tp.replies = [
		_call("resolve_place", {"name": "南门"}),
		_call("resolve_place", {"name": "北墙"}),
		_call("resolve_place", {"name": "不存在"}),
		_final([{"vehicle": NAME_A, "missions": [_goto(64.25, 64.25)]}]),
	]
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern, map, pm)
	var r: Dictionary = await _run(loop, "去南门")
	ok = _check(ok, tp.posts.size() == 4, tag, "请求数 %d 期望 4" % tp.posts.size())
	if tp.posts.size() == 4:
		var p1 := _payload(_last_tool(tp.posts[1]))
		ok = _check(ok, bool(p1.get("ok", false)) and not bool(p1.get("adjusted", true)), tag,
				"南门应 ok 且 adjusted=false，实际：" + str(p1))
		ok = _check(ok, _near(float(p1.get("x", -1.0)), 64.25) and _near(float(p1.get("y", -1.0)), 64.25),
				tag, "南门 x/y 应为格中心 (64.25,64.25)，实际：" + str(p1))
		ok = _check(ok, str(p1.get("name", "")) == "南门", tag, "南门 name 不对：" + str(p1.get("name", "")))
		var p2 := _payload(_last_tool(tp.posts[2]))
		ok = _check(ok, bool(p2.get("ok", false)) and bool(p2.get("adjusted", false)), tag,
				"北墙应 ok 且 adjusted=true，实际：" + str(p2))
		ok = _check(ok, _near(float(p2.get("x", -1.0)), 32.25) and _near(float(p2.get("y", -1.0)), 31.75),
				tag, "北墙应换到正北格中心 (32.25,31.75)，实际：" + str(p2))
		var p3 := _payload(_last_tool(tp.posts[3]))
		ok = _check(ok, not bool(p3.get("ok", true)) and str(p3.get("error", "")) == "not_found", tag,
				"不存在应 ok=false / error=not_found，实际：" + str(p3))
	ok = _check(ok, bool(r.get("ok", false)), tag, "ok 应 true（reason=%s）" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.size() == 1, tag, "帧数 %d 期望 1" % kern.calls.size())
	loop.free()
	reg.free()
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── T14 总预算耗尽 ─────────────────────────────────────────

func _test_total_budget_timeout() -> bool:
	var tag := "T14 total_budget_timeout"
	var ok := true
	var tp := FakeTransport.new()
	tp.replies = [_call("query_vehicles", {}), _final([{"vehicle": NAME_A, "missions": [_goto(3.25, 3.25)]}])]
	tp.delay_ms = 120
	var kern := FakeKernel.new()
	var reg = _reg_two()
	var loop = _loop(tp, reg, kern, null, null, {"total_budget_s": 0.05})
	var r: Dictionary = await _run(loop, "预算很短的会话")
	ok = _check(ok, not bool(r.get("ok", true)), tag, "ok 应为 false")
	ok = _check(ok, str(r.get("reason", "")) == "timeout", tag,
			"reason=%s 期望 timeout" % str(r.get("reason", "")))
	ok = _check(ok, kern.calls.is_empty(), tag, "预算耗尽却发了 %d 帧" % kern.calls.size())
	ok = _check(ok, (r.get("results", []) as Array).is_empty(), tag, "results 应为空")
	loop.free()
	reg.free()
	if ok:
		print("PASS ", tag)
	return ok
