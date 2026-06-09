extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## Renderer2D — 2D 俯视渲染器父组件
## 组装 MapContainer2D / VehicleMarker2D / PathLine2D，订阅 EventBus 信号分发。

@onready var _map: Node2D = $MapContainer2D
@onready var _vehicle: Node2D = $VehicleMarker2D
@onready var _path: Node2D = $PathLine2D


func _ready() -> void:
	var bus := get_node("/root/EventBus")
	bus.pose_received.connect(_on_pose)
	bus.voxel_received.connect(_on_voxel)
	bus.path_received.connect(_on_path)
	bus.zoom_changed.connect(_on_zoom)

	# 发出初始 zoom 值，同步 ZoomSlider
	bus.zoom_changed.emit(1.0)


func _on_zoom(zoom: float) -> void:
	var cam: Camera2D = _vehicle.get_node("Camera2D")
	cam.zoom = Vector2(zoom, zoom)


func _on_pose(pose: Dictionary) -> void:
	var x: float = pose.get("x", 0.0)
	var z: float = pose.get("z", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	_vehicle.update_pose(x, z, yaw)


func _on_voxel(voxels: Array, is_full: bool) -> void:
	if is_full:
		_map.set_full(voxels)
	else:
		_map.set_delta(voxels)


func _on_path(points: Array) -> void:
	_path.set_points(points)
