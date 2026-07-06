extends Node
## Present by KeJi
## Date: 2026-06-08
##
## InputHandler — 键盘输入 → cmd 消息
## 捕获 WASD / Space，通过 EventBus 发送 cmd 指令。

const _KEY_MAP := {
	KEY_W: "forward",
	KEY_S: "backward",
	KEY_A: "spin_left",
	KEY_D: "spin_right",
	KEY_SPACE: "stop",
}


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if key_event.echo:
		return

	if not _KEY_MAP.has(key_event.keycode):
		return

	# 只响应 press，松手发 stop
	if key_event.pressed:
		EventBus.ctrl_send.emit(_make_cmd(_KEY_MAP[key_event.keycode]))
	else:
		EventBus.ctrl_send.emit(_make_cmd("stop"))


func _make_cmd(cmd: String) -> Dictionary:
	return {"cmd": cmd}
