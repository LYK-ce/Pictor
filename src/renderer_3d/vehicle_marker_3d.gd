extends Node3D
## Present by KeJi
## Date: 2026-06-08
##
## VehicleMarker3D — 车辆 3D 标记 + CameraRig


func _ready() -> void:
	# 占位：红色 BoxMesh 作为车辆模型
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.3, 1.0)
	body.mesh = box
	body.material_override = StandardMaterial3D.new()
	body.material_override.albedo_color = Color(0.25, 0.5, 1.0)  # 蓝色
	add_child(body)


func update_pose(x: float, y: float, z: float, yaw: float) -> void:
	const SCALE := 16.0
	position = Vector3(x * SCALE, y * SCALE, z * SCALE)
	rotation.y = yaw
