extends Node2D
## Presented by KeJi
## Date: 2026-08-02
##
## AutoHandler — 自动控制：右键 Goto 广播 + 瞬态命令状态机
## 默认态：右键地图 → Goto 广播给 selected_ids
## 瞬态态：点命令按钮（如巡逻）后等待目标点，左键执行 / 右键取消

@export var app_state: AppStateResource

# 瞬态命令扩展点：点按钮进入等待态，执行完自动回 NONE
enum PendingAction { NONE, PATROL }
var _pending_action := PendingAction.NONE


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	# —— 瞬态态：等待目标点 ——
	if _pending_action != PendingAction.NONE:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_execute_pending(mb)
		# 右键 / 其他 = 取消
		_pending_action = PendingAction.NONE
		get_viewport().set_input_as_handled()
		return

	# —— 默认态：右键 = Goto ——
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if app_state.selected_ids.is_empty():
		return

	var mouse_pos := get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_pos)
	var real := CoordUtils.tile_to_real(tile.x, tile.y)

	for id in app_state.selected_ids:
		EventBus.cmd_send.emit(id,
			MessageBuilder.build_auto_push_goto(real.x, real.y))

	# 通知高亮
	EventBus.goto_issued.emit(real.x, real.y)
	get_viewport().set_input_as_handled()


func _execute_pending(_mb: InputEventMouseButton) -> void:
	# PATROL 等瞬态命令的扩展点：坐标转换 + 广播
	pass
