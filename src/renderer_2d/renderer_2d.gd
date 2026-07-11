extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## Renderer2D — 2D 俯视渲染器
## 组装 MapContainer2D / Vehicle，订阅 EventBus 信号分发。

@export var vehicle_scene: PackedScene

@onready var _map: Node2D = $MapContainer2D
@onready var _vehicle_container: Node2D = $VehicleContainer

var _vehicle_instance: Node2D = null
var _camera: Camera2D = null


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.enabled = true
	_vehicle_container.add_child(_camera)

	EventBus.pose_received.connect(_on_pose)
	EventBus.chunk_updated.connect(_on_chunk_updated)
	EventBus.zoom_changed.connect(_on_zoom)
	EventBus.ws_connected.connect(_on_ws_connected)
	EventBus.zoom_changed.emit(1.0)


func _on_ws_connected() -> void:
	if vehicle_scene and not _vehicle_instance:
		_vehicle_instance = vehicle_scene.instantiate()
		_vehicle_container.add_child(_vehicle_instance)


func _on_zoom(zoom: float) -> void:
	_camera.zoom = Vector2(zoom, zoom)


func _on_pose(pose: Dictionary) -> void:
	if not _vehicle_instance:
		return
	var x: float = pose.get("x", 0.0)
	var z: float = pose.get("z", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	_vehicle_instance.position = CoordUtils.real_to_game(x, z)
	_vehicle_instance.rotation = yaw


func _on_chunk_updated(chunk_x: int, chunk_y: int) -> void:
	var cells := %MapData2D.get_chunk_cells(chunk_x, chunk_y)
	if not cells.is_empty():
		_map.render_chunk(chunk_x, chunk_y, cells)
