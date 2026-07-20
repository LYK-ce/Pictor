extends Node3D
## Present by KeJi
## Date: 2026-06-08
##
## Renderer3D — 3D 透视渲染器父组件

@onready var _map: Node3D = $MapContainer3D
@onready var _vehicle: Node3D = $VehicleMarker3D
@onready var _path: Node3D = $PathLine3D


func _ready() -> void:
	EventBus.pose_received.connect(_on_pose)
	EventBus.voxel_received.connect(_on_voxel)
	EventBus.path_received.connect(_on_path)


func _on_pose(vehicle_id: String, pose: Dictionary) -> void:
	var x: float = pose.get("x", 0.0)
	var y: float = pose.get("y", 0.0)
	var z: float = pose.get("z", 0.0)
	var yaw: float = pose.get("yaw", 0.0)
	_vehicle.update_pose(x, y, z, yaw)


func _on_voxel(voxels: Array, is_full: bool) -> void:
	if is_full:
		_map.set_full(voxels)
	else:
		_map.set_delta(voxels)


func _on_path(points: Array) -> void:
	_path.set_points(points)
