## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## TaskApi — 任务下发层（task_51 Step 3 §4.3）：agent 的「派活」工具
## 纯静态（同 VehicleApi / MapApi 的风格）：无节点、无 Autoload、不 import 场景、不碰 EventBus，
## headless 下可 `-s` 直测。kernel / registry 都作为**入参**（不取单例、不缓存）：
##   registry — 有 `vehicles: Dictionary` 的对象（生产 = VehicleRegistry，单测 = 假表）
##   kernel   — 有 `send_command(vid: String, frame: PackedByteArray) -> bool` 的对象
##              （生产 = KernelBridge.kernel（PleiadesKernel），单测 = FakeKernel）
##
## 链路（全部复用现成件，本层只补 builder 不做的校验 + 逐车循环）：
##   missions → MessageBuilder.build_task_set → OrionMessages.Build_Cmd → kernel.send_command
## **不经 EventBus.cmd_send**：① 那条路返回不了任何东西（拿不到 sent）；② kernel_bridge.gd:64-75
## 对 targets > 1 只 push_warning，然后把**同一帧**重复发给每辆车 ⇒ 所有车去同一个点。
##
## ⚠️ 语义 ① **TASK_SET 是整队替换**，不是追加：
##   一条 TASK_SET 把该车**整个任务队列换掉**，并触发车端 `device.reset()`。
##   连续两次下发，第二次**覆盖**第一次；同一车在本批里出现两次 → 两帧按序发出、后一帧覆盖前一帧。
##   本层**不实现「追加」**：协议里没有「读回当前队列」的通道，要追加得先改协议（另开 step）。
##
## ⚠️ 语义 ② **sent 只到通道级，不是「车收到」**：
##   `kernel.send_command` 走 `Send_Data_Try`（fire-and-forget，pleiades-terminal/src/lib.rs:125），
##   返回 true 只表示「帧进了发送通道」。车端回的 `OK` ACK 在 Pictor 侧**没有接收点**
##   （上行只有 msgid 1/2/3/7，见 kernel_bridge.gd:45-58）。
##   所以 sent=true ≠ 车收到，更 ≠ 车执行成功。要真回执必须改 Rust 加一条上行消息，本步不做。
##
## ⚠️ 校验是**整批原子**的：先按固定顺序校验**全部**车，任一不合格 → **一帧都不发**
##   （results 为空、errors 非空）。理由：① 硬约束「校验失败时 kernel.calls 必须为空」在混合
##   批次下也必须无条件成立；② 半队车出动比一队车不动更难收场（车已在动，模型还可能再发一遍）。
##   **发送阶段**逐车独立：某车 send_command 返回 false 不影响其余车（通道级瞬时失败，彼此无因果），
##   该车 results 行 ok=false / reason="send_failed"，整体 ok=false。
##
## 与 Step 1 / Step 2 零耦合：只从 registry 读「车在不在线」，不读位姿、不读地图、不查寻路。

class_name TaskApi
extends RefCounted


## 世界边长（米）：世界是左闭右开 [0, WORLD_SIZE_M)，与各端 WORLD_MIN/WORLD_MAX 同口径。
## **不从 MapApi 取**：Step 3 §4.4 要求与 Step 2 零耦合（本层不读地图）。
const WORLD_SIZE_M := 128.0

## 单车单次 missions 上限：`Encode_Task_Set` 到 255 条就 printerr + **静默截断**
## （orion_messages.gd:275-277），帧里少几条没人知道 ⇒ 拼帧前就拒（mission_count 本身是 u8）。
const MAX_MISSIONS := 255

## reason 取值：前五项是 §4.3-2 的五项校验，send_failed / encode_failed 是发送阶段的两个值
const REASON_UNKNOWN_VEHICLE := "unknown_vehicle"
const REASON_UNKNOWN_TYPE := "unknown_type"
const REASON_BAD_COORD := "bad_coord"
const REASON_BAD_ARGS := "bad_args"
const REASON_KERNEL_NOT_READY := "kernel_not_ready"
const REASON_SEND_FAILED := "send_failed"
## 防御分支：校验已把 Encode_Task_Set 会拒的条件全拦了，正常路径不可达（见 _Send）
const REASON_ENCODE_FAILED := "encode_failed"


# ─── 三个入口（文档 §4.3-1）────────────────────────────────────

## 批量下发：tasks 每项 {"vehicle": "小车A"} 或 {"vid": "<hex>"}，外加 **必需** 的 "missions": [...]。
## 空 tasks = **什么都不做**（不是取消！取消某车要显式写 "missions": []，见 task_51 §6.3-7-1）。
## opt 是**保留位**（当前没有任何有效键，未知键一律忽略，与 MapApi 的 opt 同风格）。
## 返回 {ok, results:[6 键], errors:[2 键]}；ok = errors 为空且每车都 sent。
static func Dispatch(kernel, registry, tasks: Array, opt: Dictionary = {}) -> Dictionary:
	return _Dispatch(kernel, registry, tasks, false)


## 单车下发：vehicle 可为车名或 vid（解析器先按 vid 精确查，再按车名查）。
## 返回结构与 Dispatch **同形**（results / errors 各至多 1 条），上层不必写两套分支。
static func Dispatch_One(kernel, registry, vehicle: String, missions: Array) -> Dictionary:
	return _Dispatch(kernel, registry, [{"vehicle": vehicle, "missions": missions}], false)


## 取消：vehicles 每项可为**车名或 vid**（裸字符串解析，两种都认）。
## 取消帧 = mission_count 0（`MessageBuilder.build_auto_cancel()`，**唯一**取消入口）。
## vehicles == [] → **什么都不做**（保守：空数组不该把全队停车；全队取消请显式列出车名）。
static func Cancel(kernel, registry, vehicles: Array) -> Dictionary:
	return _Dispatch(kernel, registry, vehicles, true)


# ─── 内部：整批校验 → 逐车下发 ─────────────────────────────────

## is_cancel = true 时每项一律当 missions == []（取消帧），忽略入参里的 missions。
static func _Dispatch(kernel, registry, entries: Array, is_cancel: bool) -> Dictionary:
	# ① 校验全批（不 short-circuit：一次把**所有**不合格的车都报出来，模型一轮就能改对）
	var rows: Array = []
	var errors: Array = []
	for entry in entries:
		var v: Dictionary = _Validate_Entry(kernel, registry, entry, is_cancel)
		if bool(v["ok"]):
			rows.append(v)
		else:
			errors.append({"vehicle": str(v["label"]), "reason": str(v["reason"])})
	if not errors.is_empty():
		return {"ok": false, "results": [], "errors": errors}   # 一帧都不发
	# ② 逐车拼帧 + 下发（**一车一帧**，绝不把多车塞进一帧）
	var results: Array = []
	for row: Dictionary in rows:
		results.append(_Send(kernel, row))
	var ok := true
	for r: Dictionary in results:
		if not bool(r["ok"]):
			ok = false
			break
	return {"ok": ok, "results": results, "errors": []}


## 一项任务（一台车）的校验，顺序即合同：
##   ① 车在注册表 ② missions 形态 ③ 逐条 mission（type → 必填 → 坐标 → half_side）④ kernel 就绪
## 同一项多项不合格时 reason 取**先**触发的那条（单测 T13 钉住 unknown_vehicle 先于 kernel_not_ready）。
static func _Validate_Entry(kernel, registry, entry: Variant, is_cancel: bool) -> Dictionary:
	# ① 车在注册表（在表 = 在线：断连由 vehicle_unregistered 擦除，vehicle_registry.gd:48-50）
	var who: Dictionary = _Resolve_Vehicle(registry, entry)
	if not bool(who["ok"]):
		return who
	var label := str(who["name"])
	if label.is_empty():
		label = str(who["vid"])
	# ② missions 形态：**缺 "missions" 键 ≠ "missions": []** —— 后者是取消，前者是参数错。
	#    这一条是防呆：把缺键当 [] 会静默取消该车整个任务队列（最危险的默认值）。
	var missions_raw: Variant = []
	if not is_cancel:
		if not (entry is Dictionary):
			return _Fail_Entry(REASON_BAD_ARGS, label)
		var d: Dictionary = entry
		if not d.has("missions"):
			return _Fail_Entry(REASON_BAD_ARGS, label)
		missions_raw = d["missions"]
	# ③ 逐条 mission
	var mv: Dictionary = _Validate_Missions(missions_raw)
	if not bool(mv["ok"]):
		return _Fail_Entry(str(mv["reason"]), label)
	# ④ kernel 就绪放最后，保证 reason 优先级与文档 §4.3-2 表格的行序一致
	if not _Kernel_Ready(kernel):
		return _Fail_Entry(REASON_KERNEL_NOT_READY, label)
	return {
		"ok": true, "reason": "", "label": label,
		"vid": str(who["vid"]), "name": str(who["name"]), "missions": mv["missions"],
	}


## missions 数组校验 + 归一化（**只在这里**把字符串类型翻成整数，之后一律把整数交给 builder）。
## 返回 {ok, reason, missions:[归一化后的 Dictionary]}
static func _Validate_Missions(missions: Variant) -> Dictionary:
	if not (missions is Array):
		return {"ok": false, "reason": REASON_BAD_ARGS}
	var arr: Array = missions
	if arr.size() > MAX_MISSIONS:
		return {"ok": false, "reason": REASON_BAD_ARGS}
	var out: Array = []
	for m in arr:
		var one: Dictionary = _Validate_Mission(m)
		if not bool(one["ok"]):
			return {"ok": false, "reason": str(one["reason"])}
		out.append(one["item"])
	return {"ok": true, "reason": "", "missions": out}


## 单条 mission 校验 + 归一化。返回 {ok, reason, item}。顺序固定：
##   type(unknown_type) → 必填(bad_args) → 坐标(bad_coord) → half_side(bad_args)
## 「必填」在「坐标」之前不是任性：字段缺失时没有值可判有限性，只能先报 bad_args。
static func _Validate_Mission(m: Variant) -> Dictionary:
	if not (m is Dictionary):
		return {"ok": false, "reason": REASON_BAD_ARGS}
	var md: Dictionary = m
	# ① 类型白名单：**自己判**。绝不交给 ProtocolDef.Mission_Type_From 兜底——它把任何
	#    不认识的字符串返回 0（Goto），"gurad" 拼错一个字母就会静默变成「前往」（protocol_def.gd:84-97）
	var mt := _Normalize_Type(md.get("type", null))
	if mt < 0:
		return {"ok": false, "reason": REASON_UNKNOWN_TYPE}
	# ② 必填字段（存在且是数字；缺失 ≠ 0.0）
	var need: Array = ["x", "y"]
	if mt == ProtocolDef.MISSION_TYPE_CONTAINMENT:
		need = ["x", "y", "half_side"]
	elif mt == ProtocolDef.MISSION_TYPE_FACE:
		need = ["fx", "fy"]
	elif mt == ProtocolDef.MISSION_TYPE_GUARD:
		need = ["x", "y", "fx", "fy"]
	for k: String in need:
		if not _Is_Num(md.get(k, null)):
			return {"ok": false, "reason": REASON_BAD_ARGS}
	# ③ 坐标：一律按世界点校验（Face 的点是「朝向点」、Guard 是「值守点 + 注视点」，都必须在世界里）
	var pts: Array = ["x", "y"]
	if mt == ProtocolDef.MISSION_TYPE_FACE:
		pts = ["fx", "fy"]
	elif mt == ProtocolDef.MISSION_TYPE_GUARD:
		pts = ["x", "y", "fx", "fy"]
	for k: String in pts:
		if not _In_World(float(md[k])):
			return {"ok": false, "reason": REASON_BAD_COORD}
	# ④ half_side（只有 Containment 有）：有限且 > 0，与 Encode_Task_Set 的门同口径
	if mt == ProtocolDef.MISSION_TYPE_CONTAINMENT:
		var hs := float(md["half_side"])
		if not is_finite(hs) or hs <= 0.0:
			return {"ok": false, "reason": REASON_BAD_ARGS}
	# ⑤ 归一化：**Face 的 (fx, fy) 必须搬到 x / y 键** —— type=4 在字节层只有两个 f32，
	#    Encode_Task_Set 只写 x/y（orion_messages.gd:306-307）；原样带 fx/fy 会被**丢掉**，
	#    车会朝 (0, 0)。同理 Guard 的 x/y 是值守点、fx/fy 是注视点，两者都留。
	var item := {"type": mt}
	if mt == ProtocolDef.MISSION_TYPE_FACE:
		item["x"] = float(md["fx"])
		item["y"] = float(md["fy"])
	else:
		item["x"] = float(md["x"])
		item["y"] = float(md["y"])
	if mt == ProtocolDef.MISSION_TYPE_CONTAINMENT:
		item["half_side"] = float(md["half_side"])
	elif mt == ProtocolDef.MISSION_TYPE_GUARD:
		item["fx"] = float(md["fx"])
		item["fy"] = float(md["fy"])
	return {"ok": true, "reason": "", "item": item}


## 类型归一化：返回线格式整数，**不认识就 -1**（绝不回落 0 = Goto）。
## 接受三种形态：整数 / JSON 解出来的「整数值 float」（3.0）/ 字符串（大小写与首尾空白不敏感）。
static func _Normalize_Type(raw: Variant) -> int:
	if raw is int or raw is float:
		var f := float(raw)
		if not is_finite(f) or f != floorf(f):
			return -1
		var i := int(f)
		return i if _Is_Wire_Type(i) else -1
	if raw is String:
		var w := str(raw).strip_edges().to_lower()
		if w == "goto":
			return ProtocolDef.MISSION_TYPE_GOTO
		if w == "follow":
			return ProtocolDef.MISSION_TYPE_FOLLOW
		if w == "containment" or w == "contain":   # "contain" 是 protocol_def.gd:89 的既有别名
			return ProtocolDef.MISSION_TYPE_CONTAINMENT
		if w == "face":
			return ProtocolDef.MISSION_TYPE_FACE
		if w == "guard":
			return ProtocolDef.MISSION_TYPE_GUARD
	return -1


## 线格式认的 5 个 type（退役的 1 = Circle 已删、不得复用；protocol_def.gd:72-78）
static func _Is_Wire_Type(t: int) -> bool:
	return t == ProtocolDef.MISSION_TYPE_GOTO \
			or t == ProtocolDef.MISSION_TYPE_FOLLOW \
			or t == ProtocolDef.MISSION_TYPE_CONTAINMENT \
			or t == ProtocolDef.MISSION_TYPE_FACE \
			or t == ProtocolDef.MISSION_TYPE_GUARD


## 「给了数字」：int 或 float（JSON 数字一律解成 float），bool / 字符串都不算
static func _Is_Num(v: Variant) -> bool:
	return (v is int) or (v is float)


## 世界内：有限且落在左闭右开 [0, WORLD_SIZE_M)
static func _In_World(v: float) -> bool:
	return is_finite(v) and v >= 0.0 and v < WORLD_SIZE_M


# ─── 内部：车解析 / kernel 就绪 / 拼帧下发 ──────────────────────

## 解析「哪台车」：entry 是 Dictionary 时认 "vid" / "vehicle"；是裸字符串时按
## 「先 vid 后车名」查（Cancel 传裸字符串，两种都可能）。
## 返回 {ok, reason, label, vid, name}；失败时只有 reason + label。
static func _Resolve_Vehicle(registry, entry: Variant) -> Dictionary:
	var vehicles := _Vehicles(registry)
	if entry is String:
		return _Resolve_Label(vehicles, str(entry))
	if entry is Dictionary:
		var d: Dictionary = entry
		var by_vid := str(d.get("vid", ""))
		if not by_vid.is_empty():
			if vehicles.has(by_vid):
				return {"ok": true, "reason": "", "label": by_vid, "vid": by_vid,
						"name": _Name_Of(vehicles, by_vid)}
			return _Fail_Entry(REASON_UNKNOWN_VEHICLE, by_vid)
		var by_name := str(d.get("vehicle", ""))
		if by_name.is_empty():
			# 既没 vid 也没 vehicle：**参数不完整**（不是「车不存在」）
			return _Fail_Entry(REASON_BAD_ARGS, "")
		return _Resolve_Label(vehicles, by_name)
	return _Fail_Entry(REASON_BAD_ARGS, "")


## 车名 / vid 二选一解析。重名时取 **vid 字典序最小** 的一条（`vehicles` 是 Dictionary，
## 键序不保证稳定，所以必须 sort 后取首个，否则同一份注册表两次解析可能给出不同的车）。
static func _Resolve_Label(vehicles: Dictionary, text: String) -> Dictionary:
	if text.is_empty():
		return _Fail_Entry(REASON_UNKNOWN_VEHICLE, text)
	if vehicles.has(text):
		return {"ok": true, "reason": "", "label": text, "vid": text, "name": _Name_Of(vehicles, text)}
	var ids: Array = vehicles.keys()
	ids.sort()
	for vid in ids:
		if _Name_Of(vehicles, str(vid)) == text:
			return {"ok": true, "reason": "", "label": text, "vid": str(vid), "name": text}
	return _Fail_Entry(REASON_UNKNOWN_VEHICLE, text)


## 注册表里那台车的名字（原名原样返回；记录不是 Dictionary 时给 ""）
static func _Name_Of(vehicles: Dictionary, vid: String) -> String:
	var rec = vehicles.get(vid, {})
	if not (rec is Dictionary):
		return ""
	return str(rec.get("name", ""))


## 取注册表的 vehicles 字典（鸭子类型：只要对象有 `vehicles: Dictionary`）。
## 传 null / 没该属性 / 类型不对 → 空字典（空表下所有车都判 unknown_vehicle，不抛错）。
static func _Vehicles(registry) -> Dictionary:
	if registry == null:
		return {}
	var v = registry.get("vehicles")
	return v if v is Dictionary else {}


## kernel 就绪 = 非 null、是 Object、且有 send_command 方法（鸭子类型：FakeKernel 也算就绪）。
## 生产环境的 kernel 由 KernelBridge._ready 在 PleiadesKernel 类注册成功后才实例化，
## 未就绪时那个字段就是 null（kernel_bridge.gd:12 / :19）。
static func _Kernel_Ready(kernel) -> bool:
	if kernel == null:
		return false
	if not (kernel is Object):
		return false
	return kernel.has_method("send_command")


## 拼帧 + 下发**一台车**（一车一帧）。返回 results 行（6 键，文档 §4.3-4）。
static func _Send(kernel, row: Dictionary) -> Dictionary:
	var missions: Array = row["missions"]
	var cmd: Dictionary
	if missions.is_empty():
		cmd = MessageBuilder.build_auto_cancel()        # mission_count = 0 = 取消（唯一入口）
	else:
		cmd = MessageBuilder.build_task_set(missions)   # 整队替换（不是追加）
	var frame := OrionMessages.Build_Cmd(cmd)
	var out := {
		"vehicle": str(row["name"]),
		"vid": str(row["vid"]),
		"ok": false,
		"sent": false,
		"frame_bytes": 0,
		"reason": "",
	}
	if frame.is_empty():
		# 防御分支（正常不可达）：不把半帧 / 空帧交给车
		out["reason"] = REASON_ENCODE_FAILED
		return out
	out["frame_bytes"] = frame.size()
	var sent := bool(kernel.send_command(str(row["vid"]), frame))
	out["sent"] = sent
	out["ok"] = sent
	out["reason"] = "" if sent else REASON_SEND_FAILED
	return out


## 校验失败的统一形状（results 行与 errors 行都用它的一半）
static func _Fail_Entry(reason: String, label: String) -> Dictionary:
	return {"ok": false, "reason": reason, "label": label}
