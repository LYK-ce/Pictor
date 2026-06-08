extends Node
## Present by KeJi
## Date: 2026-06-08
##
## InputHandler — 键盘输入 → ctrl 消息
## 捕获 WASD / Space，通过 EventBus 发送 ctrl 指令。
## 使用 get_node("/root/EventBus") 而非 Autoload 全局名，
## 保证 headless --script 测试兼容。

const _KEY_MAP := {
	KEY_W: "w",
	KEY_S: "s",
	KEY_A: "a",
	KEY_D: "d",
	KEY_SPACE: "space",
}


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if key_event.echo:
		return

	if not _KEY_MAP.has(key_event.keycode):
		return

	var ctrl := _make_ctrl(_KEY_MAP[key_event.keycode], key_event.pressed)
	get_node("/root/EventBus").ctrl_send.emit(ctrl)


## 构造 ctrl 消息（public 便于测试直接调用）
func _make_ctrl(key: String, pressed: bool) -> Dictionary:
	return {
		"type": "ctrl",
		"key": key,
		"action": "press" if pressed else "release",
	}
