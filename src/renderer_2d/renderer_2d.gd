extends Node2D
## Presented by KeJi
## Date: 2026-09-01
##
## Renderer2D — 2D 俯视渲染器
## 组装 MapContainer2D / Vehicle，订阅 EventBus 信号分发。

@export var vehicle_scene: PackedScene
@export var helicopter_scene: PackedScene   # 无人机 sprite（node_type=uav 时替换）

@onready var _map: Node2D = $MapContainer2D
@onready var _vehicle_container: Node2D = $VehicleContainer

var _vehicles: Dictionary = {}  # {vehicle_id → Node2D}

## 多车区分色板（modulate 乘法；蓝底图上得到不同色调，可自行调整）
const VEHICLE_COLORS := [
	Color(1.0, 1.0, 1.0),     # 原蓝
	Color(0.4, 0.9, 1.0),     # 淡青
	Color(1.0, 0.5, 0.9),     # 粉紫
	Color(0.5, 1.0, 0.5),     # 淡绿
	Color(1.0, 0.9, 0.4),     # 淡黄
	Color(0.6, 0.7, 1.0),     # 淡蓝
]


func _ready() -> void:
	EventBus.pose_received.connect(_on_pose)
	EventBus.chunk_updated.connect(_on_chunk_updated)
	EventBus.cells_changed.connect(_on_cells_changed)
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)
	EventBus.peer_info_updated.connect(_on_peer_info_updated)


func _on_vehicle_registered(vehicle_id: String) -> void:
	if _vehicles.has(vehicle_id):
		return
	if not vehicle_scene:
		return
	var instance := vehicle_scene.instantiate()
	instance.name = vehicle_id
	instance.set_color(VEHICLE_COLORS[_vehicles.size() % VEHICLE_COLORS.size()])
	_vehicle_container.add_child(instance)
	_vehicles[vehicle_id] = instance
	print("[Renderer2D] vehicle registered: ", vehicle_id)


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	var instance: Node = _vehicles.get(vehicle_id)
	if instance:
		instance.queue_free()
		_vehicles.erase(vehicle_id)
		print("[Renderer2D] vehicle removed: ", vehicle_id)


## 收到节点类型 → 无人机换成直升机 sprite（默认车，其余类型保持默认）
func _on_peer_info_updated(vehicle_id: String, _peer_name: String, node_type: String) -> void:
	if node_type != "uav":
		return
	var instance: Node2D = _vehicles.get(vehicle_id)
	if not instance or not helicopter_scene:
		return
	if instance.scene_file_path == helicopter_scene.resource_path:
		return  # 已是直升机，跳过
	var new_instance := helicopter_scene.instantiate()
	new_instance.name = vehicle_id
	new_instance.position = instance.position
	new_instance.rotation = instance.rotation
	new_instance.set_color(instance.get_node("AnimatedSprite2D").modulate)  # 保留颜色
	_vehicle_container.add_child(new_instance)
	_vehicles[vehicle_id] = new_instance
	instance.queue_free()


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	var instance: Node2D = _vehicles.get(vehicle_id)
	if not instance:
		return
	var x: float = pose.get("x", 0.0)
	var y: float = pose.get("y", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	instance.apply_pose(CoordUtils.real_to_game(x, y), yaw)


func _on_chunk_updated(chunk_x: int, chunk_y: int) -> void:
	var cells: PackedByteArray = %MapData2D.get_chunk_cells(chunk_x, chunk_y)
	if cells.is_empty():
		print("[Renderer2D] chunk_updated: chunk(%d,%d) EMPTY — skipping" % [chunk_x, chunk_y])
		return
	# DEBUG（log-odds → 阈值 ±6 派生三态）
	var c_free := 0; var c_occ := 0; var c_unk := 0
	var th := ProtocolDef.LOG_ODDS_THRESHOLD
	for i in range(cells.size()):
		var lg := ChunkData2D.to_i8(cells[i])
		if lg > th: c_occ += 1
		elif lg < -th: c_free += 1
		else: c_unk += 1
	print("[Renderer2D] chunk_updated: chunk(%d,%d) cells=%d [free:%d occupied:%d unknown:%d] → render" % [chunk_x, chunk_y, cells.size(), c_free, c_occ, c_unk])
	_map.render_chunk(chunk_x, chunk_y, cells)


func _on_cells_changed(updates: Array) -> void:
	_map.update_cells(updates)
