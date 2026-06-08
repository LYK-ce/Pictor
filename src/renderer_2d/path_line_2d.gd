extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## PathLine2D — 规划路径黄色线条

@onready var _line := $Line2D as Line2D


func _ready() -> void:
	_line.default_color = Color(1.0, 0.82, 0.25)  # #ffd040
	_line.width = 2.0


## 设置路径点（世界坐标）
func set_points(points: Array) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(Vector2(p.get("x", 0.0), p.get("z", 0.0)))
	_line.points = pts
