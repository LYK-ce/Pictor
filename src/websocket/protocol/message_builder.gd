## Presented by KeJi
## Date: 2026-07-29
##
## MessageBuilder — 下行消息构造器（PC → 小车）
## 纯静态方法，无状态。构造符合协议的 JSON-serializable Dictionary。

class_name MessageBuilder
extends RefCounted


# ─── mode ──────────────────────────────────────────────────

static func build_mode_switch_to_manual() -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MODE, "action": ProtocolDef.MODE_SWITCH_TO_MANUAL}


static func build_mode_switch_to_auto() -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MODE, "action": ProtocolDef.MODE_SWITCH_TO_AUTO}


# ─── manual ────────────────────────────────────────────────

static func build_manual_forward(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": ProtocolDef.MANUAL_FORWARD, "speed": speed}


static func build_manual_backward(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": ProtocolDef.MANUAL_BACKWARD, "speed": speed}


static func build_manual_spin_left(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": ProtocolDef.MANUAL_SPIN_LEFT, "speed": speed}


static func build_manual_spin_right(speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": ProtocolDef.MANUAL_SPIN_RIGHT, "speed": speed}


static func build_manual_action(action: String, speed: int = ProtocolDef.MANUAL_DEFAULT_SPEED) -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": action, "speed": speed}
static func build_manual_stop() -> Dictionary:
	return {"cmd": ProtocolDef.CMD_MANUAL, "action": ProtocolDef.MANUAL_STOP}


# ─── auto ──────────────────────────────────────────────────

static func build_auto_push_goto(x: float, y: float) -> Dictionary:
	return {
		"cmd": ProtocolDef.CMD_AUTO,
		"action": ProtocolDef.AUTO_PUSH,
		"missions": [{"type": ProtocolDef.MISSION_GOTO, "x": x, "y": y}],
	}


static func build_auto_cancel() -> Dictionary:
	return {"cmd": ProtocolDef.CMD_AUTO, "action": ProtocolDef.AUTO_CANCEL}
