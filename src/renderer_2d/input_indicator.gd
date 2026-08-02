## Presented by KeJi
## Date: 2026-08-02
##
## InputIndicator — Goto 目标点高亮
## 监听 goto_issued，在目标 tile 上短暂高亮后淡出。

extends Node2D

var _highlight: ColorRect
var _tween: Tween


func _ready() -> void:
	EventBus.goto_issued.connect(_on_goto_issued)
	_Create_Highlight()


func _Create_Highlight() -> void:
	_highlight = ColorRect.new()
	_highlight.size = Vector2(16, 16)
	_highlight.color = Color(0.2, 0.8, 0.2, 0.4)
	_highlight.visible = false
	add_child(_highlight)


func _on_goto_issued(x: float, y: float) -> void:
	# 真实世界(米) → 游戏坐标 → 吸附 tile 中心
	var game_pos := CoordUtils.real_to_game(x, y)
	var tile := CoordUtils.game_to_tile(game_pos)
	_highlight.position = CoordUtils.tile_to_game(tile.x, tile.y) - _highlight.size / 2.0

	# 显示 + 淡出动画
	_highlight.visible = true
	_highlight.modulate.a = 1.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(0.2)                              # 保持 0.2s
	_tween.tween_property(_highlight, "modulate:a", 0.0, 0.4)  # 淡出 0.4s
	_tween.tween_callback(func() -> void: _highlight.visible = false)
