## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## AgentTools — 四个工具的注册表与 handler（task_51 Step 5 §6.3-4）
## 只做「模型给的 args → 调 Step 1~4 的 API → 裁剪后的结果」这一件事：
##   query_vehicles → VehicleApi.Query / Summary（Step 1）
##   check_passable → MapApi.Check（Step 2）
##   resolve_place  → PlaceMap.Resolve + MapApi.Check（Step 4 + Step 2）
##   dispatch_tasks → TaskApi.Dispatch（Step 3，逐车一帧、整批原子校验）
##
## ⚠️ **裁剪是硬要求**：VehicleApi.Query 一条记录 15 个字段，直接回填两三轮就把上下文窗口撑爆。
##    query_vehicles 只回 name/x/y/state；check_passable 只回 passable/nearest；
##    resolve_place 只回 x/y/adjusted/name；dispatch_tasks 只回 {vehicle, ok|reason}。
##    单条结果超过 800 字符由 AgentLoop._Encode 统一截断（本层不做截断，只保证形状小）。
##
## ⚠️ 三条语义（§6.3-7，写错就是事故）：
##   ① `tasks: []` = 什么都不做，**不是取消**（TaskApi.Dispatch 收到空数组 → 一帧不发）；
##   ② 取消某台车必须显式 `{"vehicle":"X","missions":[]}` —— `mission_count = 0` 是**唯一**取消入口；
##      「缺 missions 键」不是取消、是参数错（由 TaskApi 报 bad_args，语义只有一处）。
##   ③ 一次最多 32 台车、每台车最多 16 条 missions → **直接拒**（too_many_tasks），不交给模型解释。
##
## ⚠️ 走 TaskApi 而不走 EventBus.cmd_send：① EventBus 那条路返回不了任何东西（拿不到 sent）；
##    ② kernel_bridge 对 targets > 1 会把**同一帧**重复发给每辆车（所有车去同一个点）。
##
## ⚠️ 工具报错不中断（§6.3-6）：Exec 的**任何**分支都返回结构化字典 {ok, tool, error, result}，
##    错误原样回填给模型，让模型自己改参数（GDScript 没有 try，靠返回值传错）。

class_name AgentTools
extends RefCounted

const TOOL_QUERY := "query_vehicles"
const TOOL_PASSABLE := "check_passable"
const TOOL_PLACE := "resolve_place"
const TOOL_DISPATCH := "dispatch_tasks"
## 注册表（顺序即提示词里的顺序；单测用它反向校验 / 提示词里都提到了）
const TOOL_NAMES := [TOOL_QUERY, TOOL_PASSABLE, TOOL_PLACE, TOOL_DISPATCH]

## 三语义之③：超限**直接拒**，不交给模型解释
const MAX_TASKS := 32
const MAX_MISSIONS_PER_TASK := 16

## error 短码（稳定值，模型与单测都按它判）
const ERR_UNKNOWN_TOOL := "unknown_tool"
const ERR_BAD_ARGS := "bad_args"
const ERR_TOO_MANY_TASKS := "too_many_tasks"
const ERR_NOT_FOUND := "not_found"
const ERR_NO_PASSABLE_NEARBY := "no_passable_nearby"
const ERR_NO_PLACE_MAP := "no_place_map"
const ERR_DISPATCH_FAILED := "dispatch_failed"

## passable 只有三个词（occupied / free / 其余一律 unknown）
const WORD_FREE := "free"
const WORD_UNKNOWN := "unknown"
const WORD_OCCUPIED := "occupied"

## query_vehicles 只转发这三个 filter（§6.3-4）：max_pose_age_ms 之类会让模型把车筛空后误判「没有车」
const QUERY_FILTER_KEYS := ["name", "node_type", "busy"]

var _registry = null        # 有 vehicles: Dictionary（生产 = VehicleRegistry）
var _map_data = null        # 有 get_cell / get_chunk_cells（生产 = MapData2D）
var _place_map = null       # 有 Resolve（生产 = PlaceMap 实例）
var _kernel = null          # 有 send_command（生产 = KernelBridge.kernel）


func _init(registry = null, map_data = null, place_map = null, kernel = null) -> void:
	_registry = registry
	_map_data = map_data
	_place_map = place_map
	_kernel = kernel


## 唯一入口：{ok, tool, error, result}；**任何分支都返回字典**（工具报错不中断）
func Exec(tool: String, args: Dictionary) -> Dictionary:
	var name := str(tool).strip_edges()
	match name:
		TOOL_QUERY:
			return _Query_Vehicles(args)
		TOOL_PASSABLE:
			return _Check_Passable(args)
		TOOL_PLACE:
			return _Resolve_Place(args)
		TOOL_DISPATCH:
			return _Dispatch_Tasks(args)
	return _Fail(name, ERR_UNKNOWN_TOOL, {"ok": false, "error": ERR_UNKNOWN_TOOL})


## 三语义之③：上限检查（**final 与 dispatch_tasks 两条路共用这一个**，一处实现不会漂）
## tasks > 32 台车 或 任一车 missions > 16 条 → too_many_tasks；tasks 里有非 Dictionary 项 → bad_args。
## ⚠️ 「缺 missions 键」**不在这里判**（它不是取消，是参数错；交给 TaskApi 报 bad_args）。
## ⚠️ static：AgentLoop 的 final 路径用 preload 常量直调（AgentToolsScript.Check_Tasks_Limits）。
static func Check_Tasks_Limits(tasks: Array) -> Dictionary:
	if tasks.size() > MAX_TASKS:
		return {"ok": false, "error": ERR_TOO_MANY_TASKS}
	for entry: Variant in tasks:
		if not (entry is Dictionary):
			return {"ok": false, "error": ERR_BAD_ARGS}
		var missions: Variant = (entry as Dictionary).get("missions", null)
		if missions is Array and (missions as Array).size() > MAX_MISSIONS_PER_TASK:
			return {"ok": false, "error": ERR_TOO_MANY_TASKS}
	return {"ok": true, "error": ""}


## query_vehicles：只回 name/x/y/state（15 键记录直接回填两三轮就爆窗口）
func _Query_Vehicles(args: Dictionary) -> Dictionary:
	var filter := {}
	for key: String in QUERY_FILTER_KEYS:
		if args.has(key):
			filter[key] = args[key]
	var rows := VehicleApi.Query(_registry, filter)
	var vehicles: Array = []
	for row: Dictionary in rows:
		vehicles.append({
			"name": str(row["name"]),
			"x": snappedf(float(row["x"]), 0.01),
			"y": snappedf(float(row["y"]), 0.01),
			"state": str(row["state"]),
		})
	var s := VehicleApi.Summary(_registry)
	var summary := {
		"online": int(s["online"]), "cars": int(s["cars"]), "uavs": int(s["uavs"]),
		"idle": int(s["idle"]), "busy": int(s["busy"]),
	}
	return {
		"ok": true, "tool": TOOL_QUERY, "error": "",
		"result": {"ok": true, "vehicles": vehicles, "summary": summary},
	}


## check_passable：reason → 三个词；越界单独成错（模型据此改坐标）
func _Check_Passable(args: Dictionary) -> Dictionary:
	var x: Variant = _Num(args.get("x", null))
	var y: Variant = _Num(args.get("y", null))
	if x == null or y == null:
		return _Fail(TOOL_PASSABLE, ERR_BAD_ARGS, {"ok": false, "error": ERR_BAD_ARGS})
	var chk := MapApi.Check(_map_data, float(x), float(y))
	if not bool(chk.get("ok", false)):
		# 越界：MapApi 的 reason 就是 out_of_bounds，原样透传给模型
		var code := str(chk.get("reason", ERR_BAD_ARGS))
		return {"ok": false, "tool": TOOL_PASSABLE, "error": code, "result": {"ok": false, "error": code}}
	var nearest: Variant = null
	var near: Variant = chk.get("nearest", null)
	if near is Dictionary:
		nearest = {"x": float((near as Dictionary)["x"]), "y": float((near as Dictionary)["y"])}
	var result := {"ok": true, "passable": _Word(str(chk.get("reason", ""))), "nearest": nearest}
	return {"ok": true, "tool": TOOL_PASSABLE, "error": "", "result": result}


## resolve_place：PlaceMap.Resolve → MapApi.Check → 不能站就换 nearest 并标 adjusted
func _Resolve_Place(args: Dictionary) -> Dictionary:
	var text := str(args.get("name", "")).strip_edges()
	if text.is_empty():
		return _Fail(TOOL_PLACE, ERR_BAD_ARGS, {"ok": false, "error": ERR_BAD_ARGS})
	if _place_map == null or not _place_map.has_method("Resolve"):
		return _Fail(TOOL_PLACE, ERR_NO_PLACE_MAP, {"ok": false, "error": ERR_NO_PLACE_MAP})
	var r: Dictionary = _place_map.Resolve(text)
	if not bool(r.get("ok", false)):
		var code := str(r.get("error", ERR_NOT_FOUND))
		return {
			"ok": false, "tool": TOOL_PLACE, "error": code,
			"result": {"ok": false, "error": code, "ambiguous": r.get("ambiguous", [])},
		}
	var x := float(r["x"])
	var y := float(r["y"])
	var name := str(r["name"])
	var chk := MapApi.Check(_map_data, x, y)
	if bool(chk.get("passable", false)):
		return {
			"ok": true, "tool": TOOL_PLACE, "error": "",
			"result": {"ok": true, "x": x, "y": y, "adjusted": false, "name": name},
		}
	var near: Variant = chk.get("nearest", null)
	if not (near is Dictionary):
		return {
			"ok": false, "tool": TOOL_PLACE, "error": ERR_NO_PASSABLE_NEARBY,
			"result": {"ok": false, "error": ERR_NO_PASSABLE_NEARBY, "name": name},
		}
	return {
		"ok": true, "tool": TOOL_PLACE, "error": "",
		"result": {
			"ok": true,
			"x": float((near as Dictionary)["x"]), "y": float((near as Dictionary)["y"]),
			"adjusted": true, "name": name,
		},
	}


## dispatch_tasks：TaskApi.Dispatch（**逐车一帧**、整批原子校验）→ 只回 {vehicle, ok} / {vehicle, reason}
func _Dispatch_Tasks(args: Dictionary) -> Dictionary:
	var tasks: Variant = args.get("tasks", null)
	if not (tasks is Array):
		return _Fail(TOOL_DISPATCH, ERR_BAD_ARGS, {"ok": false, "error": ERR_BAD_ARGS})
	var lim := Check_Tasks_Limits(tasks as Array)
	if not bool(lim["ok"]):
		var code := str(lim["error"])
		return _Fail(TOOL_DISPATCH, code, {"ok": false, "error": code})
	var disp := TaskApi.Dispatch(_kernel, _registry, tasks as Array)
	var sent: Array = []
	for row: Dictionary in disp.get("results", []):
		sent.append({"vehicle": str(row.get("vehicle", "")), "ok": bool(row.get("ok", false))})
	var errors: Array = []
	for e: Dictionary in disp.get("errors", []):
		errors.append({"vehicle": str(e.get("vehicle", "")), "reason": str(e.get("reason", ""))})
	var ok := bool(disp.get("ok", false))
	return {
		"ok": ok, "tool": TOOL_DISPATCH, "error": "" if ok else ERR_DISPATCH_FAILED,
		"result": {"ok": ok, "sent": sent, "errors": errors},
	}


## reason → 词：occupied / free 各自成词，其余（unknown / no_map）一律 unknown
static func _Word(reason: String) -> String:
	if reason == MapApi.REASON_OCCUPIED:
		return WORD_OCCUPIED
	if reason == MapApi.REASON_FREE:
		return WORD_FREE
	return WORD_UNKNOWN


## 「给了数字」：int 或 float 且有限（JSON 数字一律解成 float；bool / String 不算）
static func _Num(v: Variant) -> Variant:
	if v is int:
		return float(v)
	if v is float:
		return float(v) if is_finite(float(v)) else null
	return null


static func _Fail(tool: String, code: String, result: Dictionary) -> Dictionary:
	return {"ok": false, "tool": tool, "error": code, "result": result}
