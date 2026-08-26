extends Node
## Presented by KeJi
## Date: 2026-08-02
##
## ManualHandler — 手动控制：键盘 WASD → cmd_send(manual_target)
## 捕获 WASD / Space，转换为 manual cmd，发送给手动操控车辆。

@export var app_state: AppStateResource

const _KEY_MAP := {
	KEY_W: "forward",
	KEY_S: "backward",
	KEY_A: "spin_left",
	KEY_D: "spin_right",
	KEY_SPACE: "stop",
	KEY_E: "takeoff",
	KEY_Q: "land",
}


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if key_event.echo:
		return

	if not _KEY_MAP.has(key_event.keycode):
		return

	# target 决策：无手动车则忽略
	if app_state.manual_target.is_empty():
		return

	var cmd := MessageBuilder.build_manual_stop()
	if key_event.pressed:
		cmd = MessageBuilder.build_manual_action(_KEY_MAP[key_event.keycode])
	EventBus.cmd_send.emit([app_state.manual_target] as Array[String], cmd)
