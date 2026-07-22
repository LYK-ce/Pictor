extends PanelContainer
## Present by KeJi
## Date: 2026-07-20
##
## VehiclePanel — 单车信息面板

@onready var _id_label := $VBoxContainer/ID as Label
@onready var _pose_label := $VBoxContainer/Pose as Label
@onready var _pos_label := $VBoxContainer/Position as Label
@onready var _vel_label := $VBoxContainer/Velocity as Label


func Update(vehicle_id: String, position: String, yaw: String, velocity: String) -> void:
	_id_label.text = vehicle_id
	_pos_label.text = position
	_pose_label.text = yaw
	_vel_label.text = velocity


func _on_disconnect_pressed() -> void:
	EventBus.ws_disconnect_requested.emit(_id_label.text)


func _on_control_area_gui_input(event: InputEvent) -> void:
	pass # Replace with function body.
