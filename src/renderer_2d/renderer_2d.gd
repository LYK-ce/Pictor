extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## Renderer2D — 2D 俯视渲染器
## 组装 MapContainer2D / Vehicle / PathLine2D，订阅 EventBus 信号分发。

@export var vehicle_scene: PackedScene

@onready var _map: Node2D = $MapContainer2D
@onready var _vehicle_container: Node2D = $VehicleContainer
@onready var _path: Node2D = $PathLine2D

var _vehicle_instance: Node2D = null
var _camera: Camera2D = null


func _ready() -> void:
	EventBus.pose_received.connect(_on_pose)
	EventBus.voxel_received.connect(_on_voxel)
	EventBus.path_received.connect(_on_path)
	EventBus.zoom_changed.connect(_on_zoom)
	EventBus.zoom_changed.emit(1.0)

	# 创建相机，挂在车辆容器上
	_camera = Camera2D.new()
	_camera.enabled = true
	_vehicle_container.add_child(_camera)


func _ensure_vehicle() -> Node2D:
	if not _vehicle_instance and vehicle_scene:
		_vehicle_instance = vehicle_scene.instantiate()
		_vehicle_container.add_child(_vehicle_instance)
	return _vehicle_instance


func _on_zoom(zoom: float) -> void:
	_camera.zoom = Vector2(zoom, zoom)


func _on_pose(pose: Dictionary) -> void:
	var v := _ensure_vehicle()
	if not v:
		return
	var x: float = pose.get("x", 0.0)
	var z: float = pose.get("z", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	v.position = CoordUtils.real_to_game(x, z)
	v.rotation = yaw


func _on_voxel(voxels: Array, is_full: bool) -> void:
	if is_full:
		_map.set_full(voxels)
	else:
		_map.set_delta(voxels)


func _on_path(points: Array) -> void:
	_path.set_points(points)
