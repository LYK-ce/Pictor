extends PanelContainer
## Presented by KeJi
## Date: 2026-07-20
##
## VehiclePanel — 单车信息面板

enum PanelState { NORMAL, MANUAL, AUTO }

signal panel_clicked(vehicle_id: String, ctrl_held: bool)
signal mode_toggled(vehicle_id: String, to_manual: bool)

@onready var _id_label := $VBoxContainer/ID as Label
@onready var _pose_label := $VBoxContainer/Pose as Label
@onready var _pos_label := $VBoxContainer/Position as Label
@onready var _vel_label := $VBoxContainer/Velocity as Label

var _style_normal: StyleBoxFlat
var _style_manual: StyleBoxFlat
var _style_auto: StyleBoxFlat


func _ready() -> void:
	_style_normal = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_style_manual = _style_normal.duplicate()
	_style_manual.border_color = Color(1.0, 0.5, 0.3)   # 橙色 = Manual
	_style_auto = _style_normal.duplicate()
	_style_auto.border_color = Color(0.3, 1.0, 0.5)      # 绿色 = Auto 队列
	mouse_filter = MOUSE_FILTER_PASS


func Update(vehicle_id: String, position: String, yaw: String, velocity: String) -> void:
	_id_label.text = vehicle_id
	_pos_label.text = position
	_pose_label.text = yaw
	_vel_label.text = velocity


func _on_disconnect_pressed() -> void:
	EventBus.ws_disconnect_requested.emit(_id_label.text)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.ctrl_pressed:
			panel_clicked.emit(_id_label.text, true)
			accept_event()


func set_panel_state(state: int) -> void:
	match state:
		PanelState.MANUAL:
			add_theme_stylebox_override("panel", _style_manual)
		PanelState.AUTO:
			add_theme_stylebox_override("panel", _style_auto)
		_:
			add_theme_stylebox_override("panel", _style_normal)


func set_manual_checked(checked: bool) -> void:
	$VBoxContainer/Manual.set_pressed_no_signal(checked)


func _on_manual_toggled(toggled_on: bool) -> void:
	mode_toggled.emit(_id_label.text, toggled_on)


func set_mode_label(mode: String) -> void:
	$VBoxContainer/Mode.text = mode
