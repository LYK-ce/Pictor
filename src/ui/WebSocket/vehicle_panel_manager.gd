extends VBoxContainer
## Presented by KeJi
## Date: 2026-07-28
##
## VehiclePanelManager — 管理所有车辆信息面板，以及选中状态

@export var vehicle_panel_scene: PackedScene
@export var app_state: AppStateResource

var _panels: Dictionary = {}  # {vehicle_id → Panel}


func _ready() -> void:
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.pose_received.connect(_on_pose)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	EventBus.peer_info_updated.connect(_on_peer_info_updated)


func _on_vehicle_registered(vehicle_id: String) -> void:
	if _panels.has(vehicle_id):
		return
	var panel := vehicle_panel_scene.instantiate()
	panel.name = vehicle_id
	panel.panel_clicked.connect(_on_panel_clicked)
	panel.mode_toggled.connect(_on_mode_toggled)
	add_child(panel)
	_panels[vehicle_id] = panel


func _on_panel_clicked(vehicle_id: String, ctrl_held: bool) -> void:
	if not ctrl_held:
		return

	# Ctrl+点手动车 → 切换回 auto，加入队列
	if vehicle_id == app_state.manual_target:
		_panels[vehicle_id].set_manual_checked(false)
		app_state.manual_target = ""
		EventBus.cmd_send.emit([vehicle_id] as Array[String], MessageBuilder.build_mode_switch_to_auto())
		app_state.selected_ids.append(vehicle_id)
		_update_selection()
		return

	# Ctrl+点普通车 → toggle
	if app_state.selected_ids.has(vehicle_id):
		app_state.selected_ids.erase(vehicle_id)
	else:
		app_state.selected_ids.append(vehicle_id)
	_update_selection()


func _on_mode_toggled(vehicle_id: String, to_manual: bool) -> void:
	if to_manual:
		# —— 切换为 Manual ——
		# 释放旧手动车 → 未选中
		if not app_state.manual_target.is_empty() and app_state.manual_target != vehicle_id:
			var old := app_state.manual_target
			_panels[old].set_manual_checked(false)
			EventBus.cmd_send.emit([old] as Array[String], MessageBuilder.build_mode_switch_to_auto())

		# 从 auto 队列移除
		app_state.selected_ids.erase(vehicle_id)

		# 设新手动车
		app_state.manual_target = vehicle_id
		EventBus.cmd_send.emit([vehicle_id] as Array[String], MessageBuilder.build_mode_switch_to_manual())
	else:
		# —— 切换为 Auto ——
		app_state.manual_target = ""
		EventBus.cmd_send.emit([vehicle_id] as Array[String], MessageBuilder.build_mode_switch_to_auto())
		# 不加入 selected_ids，变未选中

	_update_selection()


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	var panel: Node = _panels.get(vehicle_id)
	if panel:
		panel.queue_free()
		_panels.erase(vehicle_id)
	app_state.selected_ids.erase(vehicle_id)
	if vehicle_id == app_state.manual_target:
		app_state.manual_target = ""
	if app_state.mode == AppStateResource.Mode.FOLLOW and vehicle_id == app_state.selected_id:
		app_state.mode = AppStateResource.Mode.NONE


func _on_peer_info_updated(vehicle_id: String, peer_name: String) -> void:
	var panel = _panels.get(vehicle_id)
	if panel:
		panel.set_vehicle_name(peer_name)

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
	for id: String in _panels:
		var panel = _panels[id]
		if id == app_state.manual_target:
			panel.set_panel_state(panel.PanelState.MANUAL)
			panel.set_mode_label("Manual")
		elif app_state.selected_ids.has(id):
			panel.set_panel_state(panel.PanelState.AUTO)
			panel.set_mode_label("Auto")
		else:
			panel.set_panel_state(panel.PanelState.NORMAL)
			panel.set_mode_label("")
