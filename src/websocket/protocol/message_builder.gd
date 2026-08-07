## Presented by KeJi
## Date ： 2026-08-07
##
## MessageBuilder — 下行命令构造器（PC → 小车）
## 构造 Orion 语义的 Dictionary（含 msgid 字段），由 WebSocketManager
## 通过 OrionMessages.Build_Cmd 编码为帧发送。
## cmd_send 信号签名保持 Dictionary 不变，下游调用点零改动。

class_name MessageBuilder
extends RefCounted


# 手动动作字符串 → Orion action 枚举（兼容 input_handler 的 _KEY_MAP 字符串）
const _ACTION_STR_TO_ENUM := {
	"forward": ProtocolDef.ACTION_FORWARD,
	"backward": ProtocolDef.ACTION_BACKWARD,
	"spin_left": ProtocolDef.ACTION_SPIN_LEFT,
	"spin_right": ProtocolDef.ACTION_SPIN_RIGHT,
	"stop": ProtocolDef.ACTION_STOP,
	"beep": ProtocolDef.ACTION_BEEP,
}


# ─── ORION_MANUAL_CONTROL (msgid 4)：手动动作 + 模式切换 ──────

static func build_mode_switch_to_manual() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_SWITCH_TO_MANUAL, "param": 0}


static func build_mode_switch_to_auto() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_SWITCH_TO_AUTO, "param": 0}


static func build_manual_forward(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_FORWARD, "param": speed}


static func build_manual_backward(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_BACKWARD, "param": speed}


static func build_manual_spin_left(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_SPIN_LEFT, "param": speed}


static func build_manual_spin_right(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_SPIN_RIGHT, "param": speed}


static func build_manual_action(action: String, speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {
		"msgid": ProtocolDef.MSGID_MANUAL_CONTROL,
		"action": _ACTION_STR_TO_ENUM.get(action, ProtocolDef.ACTION_STOP),
		"param": speed,
	}


static func build_manual_stop() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_MANUAL_CONTROL, "action": ProtocolDef.ACTION_STOP, "param": 0}


## 旧格式 LLM cmd（{"cmd": "manual"/"mode"/"auto", ...}）→ Orion 语义 Dictionary
## 用于 auto_handler 聚合 LLM 输出；未知类型返回空 Dictionary
static func build_from_llm(cmd: Dictionary) -> Dictionary:
	var cmd_type: String = cmd.get("cmd", "")
	match cmd_type:
		"manual":
			return build_manual_action(cmd.get("action", ""), cmd.get("speed", ProtocolDef.MANUAL_DEFAULT_SPEED))
		"mode":
			var mode_action: String = cmd.get("action", "")
			if mode_action == "switch_to_manual":
				return build_mode_switch_to_manual()
			if mode_action == "switch_to_auto":
				return build_mode_switch_to_auto()
			return {}  # 未知 mode action，拒绝下发
		"auto":
			var auto_action: String = cmd.get("action", "")
			if auto_action == "cancel":
				return build_auto_cancel()
			return build_task_set(cmd.get("missions", []))
		_:
			return {}


# ─── ORION_TASK_SET (msgid 5)：任务队列整体替换 ────────────────

static func build_auto_push_goto(x: float, y: float) -> Dictionary:
	return {
		"msgid": ProtocolDef.MSGID_TASK_SET,
		"missions": [{"type": ProtocolDef.MISSION_TYPE_GOTO, "x": x, "y": y}],
	}


## 一次下发多条任务（LLM 指令聚合用），整体替换语义
## mission type 归一化：LLM 输出字符串 "goto" → 整数 MISSION_TYPE_GOTO（防御性）
static func build_task_set(missions: Array) -> Dictionary:
	var normalized: Array = []
	for m in missions:
		normalized.append({
			"type": _Normalize_Mission_Type(m.get("type", ProtocolDef.MISSION_TYPE_GOTO)),
			"x": m.get("x", 0.0),
			"y": m.get("y", 0.0),
		})
	return {"msgid": ProtocolDef.MSGID_TASK_SET, "missions": normalized}


static func _Normalize_Mission_Type(t) -> int:
	if t is String:
		return ProtocolDef.MISSION_TYPE_GOTO
	return int(t)


## count = 0 → 取消全部任务，停车待命
static func build_auto_cancel() -> Dictionary:
	return {"msgid": ProtocolDef.MSGID_TASK_SET, "missions": []}
