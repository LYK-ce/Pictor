extends Node
## Presented by KeJi
## Date: 2026-07-22
##
## ControlMaster — 控制总管
## 监听选中状态变化，接收 InputHandler 的键盘输入，通过 EventBus 下发 cmd 到 WebSocketManager。

@export var app_state: AppStateResource

var _selected_id := ""


func _ready() -> void:
	EventBus.vehicle_control_changed.connect(_on_vehicle_control_changed)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	$InputHandler.ctrl_input.connect(_on_ctrl_input)


func _on_vehicle_control_changed(vehicle_id: String) -> void:
	_selected_id = vehicle_id
	if vehicle_id.is_empty():
		print("[ControlMaster] deselected")
	else:
		print("[ControlMaster] selected: ", vehicle_id)


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	if vehicle_id == _selected_id:
		_selected_id = ""
		print("[ControlMaster] selected vehicle disconnected, deselected")


func _on_ctrl_input(cmd: Dictionary) -> void:
	if _selected_id.is_empty():
		return
	EventBus.cmd_send.emit(_selected_id, cmd)
