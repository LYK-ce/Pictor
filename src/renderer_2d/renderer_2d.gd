extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## Renderer2D — 2D 俯视渲染器
## 组装 MapContainer2D / Vehicle，订阅 EventBus 信号分发。

@export var vehicle_scene: PackedScene

@onready var _map: Node2D = $MapContainer2D
@onready var _vehicle_container: Node2D = $VehicleContainer

var _vehicles: Dictionary = {}  # {vehicle_id → Node2D}


func _ready() -> void:
	EventBus.pose_received.connect(_on_pose)
	EventBus.chunk_updated.connect(_on_chunk_updated)
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.vehicle_unregistered.connect(_on_vehicle_unregistered)


func _on_vehicle_registered(vehicle_id: String, _url: String) -> void:
	if _vehicles.has(vehicle_id):
		return
	if not vehicle_scene:
		return
	var instance := vehicle_scene.instantiate()
	instance.name = vehicle_id
	_vehicle_container.add_child(instance)
	_vehicles[vehicle_id] = instance
	print("[Renderer2D] vehicle registered: ", vehicle_id)


func _on_vehicle_unregistered(vehicle_id: String) -> void:
	var instance: Node = _vehicles.get(vehicle_id)
	if instance:
		instance.queue_free()
		_vehicles.erase(vehicle_id)
		print("[Renderer2D] vehicle removed: ", vehicle_id)


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	var instance: Node2D = _vehicles.get(vehicle_id)
	if not instance:
		return
	var x: float = pose.get("x", 0.0)
	var y: float = pose.get("y", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	instance.position = CoordUtils.real_to_game(x, y)
	instance.rotation = yaw


func _on_chunk_updated(chunk_x: int, chunk_y: int) -> void:
	var cells: PackedByteArray = %MapData2D.get_chunk_cells(chunk_x, chunk_y)
	if cells.is_empty():
		print("[Renderer2D] chunk_updated: chunk(%d,%d) EMPTY — skipping" % [chunk_x, chunk_y])
		return
	# DEBUG
	var c0 := 0; var c1 := 0; var c2 := 0
	for i in range(cells.size()):
		match cells[i]:
			0: c0 += 1
			1: c1 += 1
			2: c2 += 1
	print("[Renderer2D] chunk_updated: chunk(%d,%d) cells=%d [0:%d 1:%d 2:%d] → render" % [chunk_x, chunk_y, cells.size(), c0, c1, c2])
	_map.render_chunk(chunk_x, chunk_y, cells)
