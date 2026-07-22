extends PanelContainer
## Presented by KeJi
## Date: 2026-07-20
##
## VehiclePanel — 单车信息面板

signal clicked(vehicle_id: String)

@onready var _id_label := $VBoxContainer/ID as Label
@onready var _pose_label := $VBoxContainer/Pose as Label
@onready var _pos_label := $VBoxContainer/Position as Label
@onready var _vel_label := $VBoxContainer/Velocity as Label
@onready var _control_area := $Control_Area as ColorRect

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	_style_normal = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_style_selected = _style_normal.duplicate()
	_style_selected.border_color = Color(0.3, 0.5, 1.0)

	_control_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_control_area.gui_input.connect(_on_control_area_gui_input)


func Update(vehicle_id: String, position: String, yaw: String, velocity: String) -> void:
	_id_label.text = vehicle_id
	_pos_label.text = position
	_pose_label.text = yaw
	_vel_label.text = velocity


func _on_disconnect_pressed() -> void:
	EventBus.ws_disconnect_requested.emit(_id_label.text)


func _on_control_area_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		print("[VehiclePanel] clicked: ", _id_label.text)
		clicked.emit(_id_label.text)


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)


func _on_take_control_pressed() -> void:
	pass # Replace with function body.
