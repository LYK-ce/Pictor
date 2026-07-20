extends VBoxContainer
## Present by KeJi
## Date: 2026-07-20
##
## VehiclePanelManager — 管理所有车辆信息面板

@export var vehicle_panel_scene: PackedScene

var _panels: Dictionary = {}  # {vehicle_id → Panel}


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.pose_received.connect(_on_pose)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)


func _on_vehicle_registered(vehicle_id: String, _url: String) -> void:
	if _panels.has(vehicle_id):
		return
	var panel := vehicle_panel_scene.instantiate()
	panel.name = vehicle_id
	add_child(panel)
	_panels[vehicle_id] = panel


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	var panel: Node = _panels.get(vehicle_id)
	if panel:
		panel.queue_free()
		_panels.erase(vehicle_id)


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
