## Presented by KeJi
## Date ： 2026-08-06
##
## Scale — 坐标标尺总控
## 1) 驱动 x_axis / y_axis 随相机变换（平移/缩放）实时重绘
## 2) 左下角状态栏：实时显示鼠标所在 tile 格子坐标 + 世界坐标

class_name Scale
extends Control

## 活动相机（自动获取，无需手动注入）
@onready var camera: Camera2D = get_viewport().get_camera_2d()

@onready var x_axis: Control = $x_axis
@onready var y_axis: Control = $y_axis
@onready var status_label: Label = $PanelContainer/Label

## 相机变换缓存（变化时才重绘，避免每帧强刷）
var _last_center := Vector2.INF
var _last_zoom := Vector2.INF


func _ready() -> void:
	if camera == null:
		printerr("[Scale] 未找到活动 Camera2D，标尺暂不可用")
	else:
		_inject_camera()


func _process(_delta: float) -> void:
	# 相机后加入场景时的兜底
	if camera == null:
		camera = get_viewport().get_camera_2d()
		if camera == null:
			return
		_inject_camera()

	# 相机变换变化 → 重绘两个标尺
	var center := camera.get_screen_center_position()
	var zoom := camera.zoom
	if center != _last_center or zoom != _last_zoom:
		_last_center = center
		_last_zoom = zoom
		x_axis.queue_redraw()
		y_axis.queue_redraw()

	# 状态栏：鼠标所在 tile 格子 + 世界坐标
	var mouse_world := camera.get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_world)
	status_label.text = "格子: (%d, %d)  世界: (%.0f, %.0f)" % [tile.x, tile.y, mouse_world.x, mouse_world.y]


func _inject_camera() -> void:
	(x_axis as AxisRuler).camera = camera
	(y_axis as AxisRuler).camera = camera
