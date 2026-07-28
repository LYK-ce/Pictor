## Presented by KeJi
## Date ： 2026-07-28
##
## InputIndicator — Goto 模式输入指示器
## 挂载在 Renderer2D 下，监听 mode_transited，
## Goto 时显示 tile 高亮框，点击下发 goto 命令。

extends Node2D

@export var app_state: AppStateResource

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


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.ACTIVE:
		return
	if not app_state:
		return

	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var mouse_pos := get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_pos)
	var real := CoordUtils.tile_to_real(tile.x, tile.y)

	EventBus.cmd_send.emit(app_state.selected_id, {
		"cmd": "goto",
		"x": real.x,
		"y": real.y
	})

	app_state.mode = AppStateResource.Mode.NONE
	get_viewport().set_input_as_handled()