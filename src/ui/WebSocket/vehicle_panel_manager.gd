extends VBoxContainer
## Presented by KeJi
## Date: 2026-07-22
##
## VehiclePanelManager — 管理所有车辆信息面板，以及选中状态

@export var vehicle_panel_scene: PackedScene

var _panels: Dictionary = {}  # {vehicle_id → Panel}
var _selected_id := ""


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.pose_received.connect(_on_pose)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)


func _on_vehicle_registered(vehicle_id: String, _url: String) -> void:
	if _panels.has(vehicle_id):
		return
	var panel := vehicle_panel_scene.instantiate()
	panel.name = vehicle_id
	panel.get_node("Control_Area").gui_input.connect(_on_panel_gui_input.bind(vehicle_id))
	add_child(panel)
	_panels[vehicle_id] = panel


func _on_panel_gui_input(event: InputEvent, vehicle_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# 切换逻辑：点击同一辆车 → 取消选中；否则切换
	if vehicle_id == _selected_id:
		_selected_id = ""
	else:
		_selected_id = vehicle_id

	_update_selection()
	EventBus.vehicle_control_changed.emit(_selected_id)


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	var panel: Node = _panels.get(vehicle_id)
	if panel:
		panel.queue_free()
		_panels.erase(vehicle_id)
	if vehicle_id == _selected_id:
		_selected_id = ""
		EventBus.vehicle_control_changed.emit("")


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	var panel = _panels.get(vehicle_id)
	if not panel:
		return
	var x: float = pose.get("x", 0.0)
	var y: float = pose.get("y", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	var vx: float = pose.get("vx", 0.0)
	var vy: float = pose.get("vy", 0.0)
	panel.Update(vehicle_id, "%.1f, %.1f" % [x, y], "%.1f°" % rad_to_deg(yaw), "%.1f, %.1f" % [vx, vy])


func _update_selection() -> void:
	for id in _panels:
		_panels[id].set_selected(id == _selected_id)
