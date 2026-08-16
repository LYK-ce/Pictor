extends PanelContainer
## Presented by KeJi
## Date: 2026-08-16
##
## VehiclePanel — 单车信息面板

enum PanelState { NORMAL, MANUAL, AUTO }

signal panel_clicked(vehicle_id: String, ctrl_held: bool)
signal mode_toggled(vehicle_id: String, to_manual: bool)

@onready var _id_label := $VBoxContainer/ID as Label
@onready var _pose_label := $VBoxContainer/Pose as Label
@onready var _pos_label := $VBoxContainer/Position as Label
@onready var _vel_label := $VBoxContainer/Velocity as Label

## 车辆身份键（hex peer_id）与显示名分离：显示名会被 peer_info_updated 覆盖，vehicle_id 用于点选/模式切换
var _vehicle_id := ""
var _display_name := "连接中"

var _style_normal: StyleBoxFlat
var _style_manual: StyleBoxFlat
var _style_auto: StyleBoxFlat


func _ready() -> void:
	_style_normal = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_style_manual = _style_normal.duplicate()
	_style_manual.border_color = Color(1.0, 0.5, 0.3)   # 橙色 = Manual
	_style_auto = _style_normal.duplicate()
	_style_auto.border_color = Color(0.3, 1.0, 0.5)      # 绿色 = Auto 队列
	_id_label.text = _display_name
	mouse_filter = MOUSE_FILTER_PASS


func Update(vehicle_id: String, position: String, yaw: String, velocity: String) -> void:
	_vehicle_id = vehicle_id
	_id_label.text = _display_name
	_pos_label.text = position
	_pose_label.text = yaw
	_vel_label.text = velocity


## 收到 peer_info_updated → 更新显示名（不覆盖 vehicle_id）
func set_vehicle_name(peer_name: String) -> void:
	if peer_name.is_empty():
		return
	_display_name = peer_name
	_id_label.text = peer_name


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.ctrl_pressed:
			panel_clicked.emit(_vehicle_id, true)
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
	mode_toggled.emit(_vehicle_id, toggled_on)


func set_mode_label(mode: String) -> void:
	$VBoxContainer/Mode.text = mode
