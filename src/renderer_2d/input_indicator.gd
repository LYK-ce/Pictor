## Presented by KeJi
## Date ： 2026-07-29
##
## InputIndicator — Goto 模式 tile 高亮框
## 挂载在 Renderer2D 下，监听 mode_transited，
## Goto 时显示绿色半透明高亮框跟随鼠标吸附 tile。

extends Node2D

enum State { IDLE, ACTIVE }
var _state := State.IDLE

var _highlight: ColorRect


func _ready() -> void:
	EventBus.mode_transited.connect(_on_mode_transited)
	_Create_Highlight()


func _Create_Highlight() -> void:
	_highlight = ColorRect.new()
	_highlight.size = Vector2(16, 16)
	_highlight.color = Color(0.2, 0.8, 0.2, 0.4)
	_highlight.visible = false
	add_child(_highlight)


func _on_mode_transited(mode: int) -> void:
	if mode == AppStateResource.Mode.GOTO:
		_state = State.ACTIVE
		_highlight.visible = true
	else:
		_state = State.IDLE
		_highlight.visible = false


func _process(_delta: float) -> void:
	if _state != State.ACTIVE:
		return
	var mouse_pos := get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_pos)
	_highlight.position = CoordUtils.tile_to_game(tile.x, tile.y) - _highlight.size / 2.0
