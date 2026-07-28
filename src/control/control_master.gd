extends Node
## Presented by KeJi
## Date: 2026-07-28
##
## ControlMaster — 控制总管
## 接收 InputHandler 的键盘输入，通过 EventBus 下发 cmd 到 WebSocketManager。

@export var app_state: AppStateResource


func _ready() -> void:
	$InputHandler.ctrl_input.connect(_on_ctrl_input)


func _on_ctrl_input(cmd: Dictionary) -> void:
	if app_state.selected_id.is_empty():
		return
	EventBus.cmd_send.emit(app_state.selected_id, cmd)
