extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## VehicleMarker2D — 车辆蓝色三角形标记 + Camera2D 跟随


func _ready() -> void:
	var cam: Camera2D = $Camera2D
	cam.enabled = true


func _draw() -> void:
	var col := Color(0.25, 0.5, 1.0)  # #4080ff
	var pts := PackedVector2Array([
		Vector2(10, 0),
		Vector2(-5, -5),
		Vector2(-5, 5),
	])
	draw_polygon(pts, [col])


## 更新位置和朝向
func update_pose(x: float, z: float, yaw: float) -> void:
	position = Vector2(x, z)
	rotation = yaw
