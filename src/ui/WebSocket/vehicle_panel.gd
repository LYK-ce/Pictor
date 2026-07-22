extends PanelContainer
## Presented by KeJi
## Date: 2026-07-20
##
## VehiclePanel — 单车信息面板

signal take_control_toggled(vehicle_id: String, pressed: bool)

@onready var _id_label := $VBoxContainer/ID as Label
@onready var _pose_label := $VBoxContainer/Pose as Label
@onready var _pos_label := $VBoxContainer/Position as Label
@onready var _vel_label := $VBoxContainer/Velocity as Label
@onready var _btn_take := %TakeControl as Button

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	_style_normal = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(0.3, 0.5, 1.0)


func Update(vehicle_id: String, position: String, yaw: String, velocity: String) -> void:
	_id_label.text = vehicle_id
	_pos_label.text = position
	_pose_label.text = yaw
	_vel_label.text = velocity


func _on_disconnect_pressed() -> void:
	EventBus.ws_disconnect_requested.emit(_id_label.text)


func _on_take_control_toggled(pressed: bool) -> void:
	print("[VehiclePanel] take_control_toggled: ", _id_label.text, " pressed=", pressed)
	take_control_toggled.emit(_id_label.text, pressed)


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)


func set_pressed(pressed: bool) -> void:
	_btn_take.set_pressed_no_signal(pressed)
