## Presented by KeJi
## Date ： 2026-08-06
##
## AxisRuler — 单轴标尺条（x_axis / y_axis 共用）
## 覆写 _draw() 绘制：半透明深色背景 + 刻度线 + 数字
## 刻度：每 1 格小刻度（无数字），每 8 格主刻度 + 数字；缩放过密时自动跳 16/32 格

class_name AxisRuler
extends Control

## true = X 轴（顶部横向标尺），false = Y 轴（左侧纵向标尺）
@export var is_x_axis := true

## 相机引用（由 Scale 根脚本注入）
var camera: Camera2D

## 刻度样式常量
const TICK_MAJOR_COLOR := Color(1.0, 1.0, 1.0, 0.9)  # 主刻度线 / 数字
const TICK_MINOR_COLOR := Color(1.0, 1.0, 1.0, 0.4)  # 小刻度线
const BG_COLOR := Color(0.08, 0.1, 0.14, 0.75)       # 半透明深色底
const FONT_SIZE := 11

## 主刻度最小像素间距（小于此值则跳大间隔）
const MIN_TICK_SPACING_PX := 40.0

## 当前主刻度间隔（tile 数）：8 / 16 / 32
var _step := 8


func _draw() -> void:
	# 半透明深色背景
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if camera == null:
		return

	var ct := camera.get_canvas_transform()
	var view_size := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	var zoom := camera.zoom
	var tile := CoordUtils.TILE_SIZE

	# 密度保护：主刻度间距过小时自动跳大
	var zoom_axis := zoom.x if is_x_axis else zoom.y
	_step = 8
	while _step * tile * zoom_axis < MIN_TICK_SPACING_PX and _step < 64:
		_step *= 2

	var font := ThemeDB.fallback_font
	var half_w := view_size.x * 0.5 / zoom.x
	var half_h := view_size.y * 0.5 / zoom.y

	if is_x_axis:
		var gx0 := floori((center.x - half_w) / tile) - 1
		var gx1 := floori((center.x + half_w) / tile) + 1
		for gx in range(gx0, gx1 + 1):
			var sx := (ct * Vector2(gx * tile, 0.0)).x
			if gx % _step == 0:
				# 主刻度：长线 + 数字（数字在刻度线右侧）
				draw_line(Vector2(sx, size.y - 16.0), Vector2(sx, size.y), TICK_MAJOR_COLOR, 1.0)
				draw_string(font, Vector2(sx + 3.0, size.y - 5.0), str(gx), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TICK_MAJOR_COLOR)
			else:
				# 小刻度：短线
				draw_line(Vector2(sx, size.y - 7.0), Vector2(sx, size.y), TICK_MINOR_COLOR, 1.0)
	else:
		var gy0 := floori((center.y - half_h) / tile) - 1
		var gy1 := floori((center.y + half_h) / tile) + 1
		for gy in range(gy0, gy1 + 1):
			var sy := (ct * Vector2(0.0, gy * tile)).y
			if gy % _step == 0:
				# 主刻度：长线 + 数字（数字在刻度线下方）
				draw_line(Vector2(size.x - 16.0, sy), Vector2(size.x, sy), TICK_MAJOR_COLOR, 1.0)
				draw_string(font, Vector2(3.0, sy - 5.0), str(gy), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TICK_MAJOR_COLOR)
			else:
				draw_line(Vector2(size.x - 7.0, sy), Vector2(size.x, sy), TICK_MINOR_COLOR, 1.0)
