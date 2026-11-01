## Presented by KeJi
## Created Date ： 2026-08-07
## Modified Date ： 2026-11-01
##
## MessageBuilder — 下行命令构造器（PC → 小车）
## 构造 Orion 语义的 Dictionary（含 msgid 字段），由 WebSocketManager
## 通过 OrionMessages.Build_Cmd 编码为帧发送。
## cmd_send 信号签名保持 Dictionary 不变，下游调用点零改动。
## task_44 Step 3：手动改两轴 (v, omega) 的 `build_manual_motion`，模式切换改走 `msgid 8`；
##                 旧的运动枚举 builder（forward/backward/spin_*/stop）已删、不得恢复。

class_name MessageBuilder
extends RefCounted


# ─── ORION_MANUAL_CONTROL (msgid 4)：两轴连续量 + 事件 ──────
## task_44 §1.2 #3：8 B 运动（v f32 BE + omega f32 BE）/ 3 B 事件（action u8 + param i16 BE）。
## 量级 v=0.45、|omega|=0.5 由调用方按 §1.4 的表填（本函数**不做**换算、不夹取）。

static func build_manual_motion(v: float, omega: float) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "v": v, "omega": omega}


## 事件类动作（beep / start_lidar / stop_lidar / takeoff / land）；action 走 ProtocolDef.ACTION_* 常量，
## 非法 action 由 `Encode_Manual_Event` 报错并不发帧（本函数不造白名单）。
static func build_manual_event(action: int, param: int = 0) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": action, "param": param}


# ─── ORION_MODE (msgid 8)：模式切换（task_44 §1.2 #4）─────────
## 1 B（0 手动 / 1 自动）；**不再**走 msgid 4 的 action 8/9（枚举已删）。

static func build_mode_switch_manual() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MODE, "mode": ProtocolDef.MODE_MANUAL}


static func build_mode_switch_auto() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MODE, "mode": ProtocolDef.MODE_AUTO}


# ─── ORION_TASK_SET (msgid 5)：任务队列整体替换（一帧 = 一辆车）─────────

## task_36 §12.7：地面站逐车算点、逐车单独发帧 —— 每帧 missions[0] 就是该车自己的点；
## 名单段已从协议删除（§十一 #28）。
static func build_auto_push_goto(x: float, y: float) -> Dictionary:
	return {
		"msgid": ProtocolDef.MSGID_TASK_SET,
		"missions": [{"type": ProtocolDef.MISSION_TYPE_GOTO, "x": x, "y": y}],
	}


## 一次下发多条任务（LLM 指令聚合用），整体替换语义
## mission type 归一化：LLM 输出 "goto"/"follow"/"containment" → 整数；未知字符串仍 → 0（防御性）；
## int 原样交给 Encode 门控
## type 契约 = {0 Goto, 2 Follow, 3 Containment}；不在其中的由 Encode_Task_Set **报错并不发帧**
## （单一门控点，本函数不造白名单）；`half_side` 只有条目自带时才拷（type=3 必须带，由 Encode 校验）
static func build_task_set(missions: Array) -> Dictionary:
	var normalized: Array = []
	for m in missions:
		var one := {
			"type": _Normalize_Mission_Type(m.get("type", ProtocolDef.MISSION_TYPE_GOTO)),
			"x": m.get("x", 0.0),
			"y": m.get("y", 0.0),
		}
		if m.has("half_side"):
			one["half_side"] = m.get("half_side")
		normalized.append(one)
	return {"msgid": ProtocolDef.MSGID_TASK_SET, "missions": normalized}


static func _Normalize_Mission_Type(t) -> int:
	return ProtocolDef.Mission_Type_From(t)


## count = 0 → 取消全部任务，停车待命
static func build_auto_cancel() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_TASK_SET, "missions": []}


# ─── ORION_MAP_FULL (msgid 2)：终端返还合并全量（阶段 2 多车聚合）────

## 下发合并全量给新车：data = 本地合并 log-odds 表（65536B，u8 位模式）。
## ⚠️ 元数据硬约束（车端 handle_map_full 严格校验，偏离即静默忽略）：
##    origin=(0,0) / width=256 / height=256 / resolution=0.5。
static func build_map_full(cells: PackedByteArray, origin_gx := 0, origin_gy := 0,
		width := ProtocolDef.MAP_WIDTH, height := ProtocolDef.MAP_HEIGHT,
		resolution := ProtocolDef.MAP_RESOLUTION) -> Dictionary:
	return {
		"msgid": ProtocolDef.MSGID_MAP_FULL,
		"origin_gx": origin_gx, "origin_gy": origin_gy,
		"width": width, "height": height,
		"resolution": resolution, "data": cells,
	}
