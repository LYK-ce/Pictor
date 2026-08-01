extends Node2D
## Presented by KeJi
## Date ： 2026-07-29
##
## ControlMaster — 控制总管
## 接收 InputHandler 键盘输入 + Goto 点击，通过 EventBus 下发 cmd。

@export var app_state: AppStateResource

enum State { IDLE, GOTO }
var _state := State.IDLE


func _ready() -> void:
	$InputHandler.ctrl_input.connect(_on_ctrl_input)
	EventBus.mode_transited.connect(_on_mode_transited)


func _on_mode_transited(mode: int) -> void:
	if mode == AppStateResource.Mode.GOTO:
		_state = State.GOTO
	else:
		_state = State.IDLE


func _on_ctrl_input(cmd: Dictionary) -> void:
	if app_state.selected_id.is_empty():
		return
	EventBus.cmd_send.emit(app_state.selected_id, cmd)


func _input(event: InputEvent) -> void:
	if _state != State.GOTO:
		return
	if app_state.selected_ids.is_empty():
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return

		var mouse_pos := get_global_mouse_position()
		var tile := CoordUtils.game_to_tile(mouse_pos)
		var real := CoordUtils.tile_to_real(tile.x, tile.y)

		for id in app_state.selected_ids:
			EventBus.cmd_send.emit(id,
				MessageBuilder.build_auto_push_goto(real.x, real.y))

		app_state.mode = AppStateResource.Mode.NONE
		get_viewport().set_input_as_handled()