## Presented by KeJi
## Date ： 2026-07-29
##
## Protocol — WebSocket 协议编码/解码
## 所有组件通过 Protocol 静态方法操作，不裸拼 JSON。

class_name Protocol
extends RefCounted


# ── 编码（PC → 小车）──

## 模式切换
static func mode_switch_to_auto() -> Dictionary:
	return {"cmd": "mode", "action": "switch_to_auto"}


static func mode_switch_to_manual() -> Dictionary:
	return {"cmd": "mode", "action": "switch_to_manual"}


## 手动控制
static func manual(action: String, speed: int = 50) -> Dictionary:
	if action == "stop":
		return {"cmd": "manual", "action": "stop"}
	return {"cmd": "manual", "action": action, "speed": speed}


## 自动任务 — Goto
static func auto_goto(x: float, y: float) -> Dictionary:
	return {
		"cmd": "auto",
		"action": "push",
		"missions": [{"type": "goto", "x": x, "y": y}]
	}


## 自动任务 — 取消
static func auto_cancel() -> Dictionary:
	return {"cmd": "auto", "action": "cancel"}


# ── 解码（小车 → PC）──

## 解析收到的文本消息，返回解析后的 Dictionary（{} 表示失败）
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.get_data()
	if not data is Dictionary:
		return {}
	return data
