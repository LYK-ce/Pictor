extends Node
## Presented by KeJi
## Date: 2026-06-08
##
## InputHandler — 键盘输入 → cmd 指令
## 捕获 WASD / Space，通过内部信号 ctrl_input 发送 cmd 指令。

signal ctrl_input(cmd: Dictionary)

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

	if key_event.pressed:
		ctrl_input.emit({"cmd": _KEY_MAP[key_event.keycode]})
	else:
		ctrl_input.emit({"cmd": "stop"})
