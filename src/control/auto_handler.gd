extends Node2D
## Presented by KeJi
## Date: 2026-08-05
##
## AutoHandler — 自动控制编排：
## 1. 右键 Goto 广播给 selected_ids（原有）
## 2. LLM 指令编排：监听 EventBus.command_requested → 调 util.llm.generate_cmds
##    → 接收 cmds_generated → 广播下发（与 Goto 同层）
## 瞬态态：点命令按钮（如巡逻）后等待目标点，左键执行 / 右键取消

@export var app_state: AppStateResource

## 工具箱引用（运行时获取，Main/Util）
@onready var util := get_node("../../Util") as Util

# 瞬态命令扩展点：点按钮进入等待态，执行完自动回 NONE
enum PendingAction { NONE, PATROL, CIRCLE }
var _pending_action := PendingAction.NONE


func _ready() -> void:
	EventBus.command_requested.connect(_on_command_requested)
	# 延迟到所有节点 _ready 完成后连接 LLM 信号（util.llm 的 @onready 此时才赋值）
	_connect_llm_signals.call_deferred()


func _connect_llm_signals() -> void:
	if util == null or util.llm == null:
		printerr("[AutoHandler] util/llm 不可用，LLM 信号未连接")
		return
	util.llm.cmds_generated.connect(_on_cmds_generated)
	util.llm.request_failed.connect(_on_request_failed)


## 收到 TextInput 等输入源的指令请求 → 调用 LLM 翻译
func _on_command_requested(text: String) -> void:
	if util == null or util.llm == null:
		printerr("[AutoHandler] util/llm 不可用")
		return
	util.llm.generate_cmds(text)


## LLM 翻译成功 → 广播下发（空数组 / 未选中车辆时不下发，仅日志）
## LLM 输出为任务序列（missions JSON 数组）：所有任务合并为一条 TASK_SET 整体下发
## mission type 归一化（字符串 "goto" → 0）在 MessageBuilder.build_task_set 内
## 注意：取消（count=0）由 UI 显式触发；LLM 输出空数组表示"无任务"，不下发
func _on_cmds_generated(cmds: Array) -> void:
	if cmds.is_empty():
		print("[AutoHandler] LLM 无有效指令，不下发")
		return
	if app_state.selected_ids.is_empty():
		print("[AutoHandler] 未选中车辆，指令不下发")
		return

	# Task 22：对选中车群发（单条 TASK_SET，members 由 WebSocketManager 按 targets 填充）
	var task_set := MessageBuilder.build_task_set(cmds)
	EventBus.cmd_send.emit(app_state.selected_ids, task_set)
	print("[LLM] → ", app_state.selected_ids, ": TASK_SET x", cmds.size())


## LLM 请求失败 → 仅日志
func _on_request_failed(msg: String) -> void:
	printerr("[AutoHandler] LLM 请求失败: ", msg)


func _unhandled_input(event: InputEvent) -> void:
	# Z 键进入 Circle 待命；Esc 取消待命
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_Z:
				_pending_action = PendingAction.CIRCLE
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ESCAPE and _pending_action != PendingAction.NONE:
				_pending_action = PendingAction.NONE
				get_viewport().set_input_as_handled()
		return

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

	# Task 22：对选中车群发（单条 TASK_SET，members 由 WebSocketManager 按 targets 填充，车端自行散布）
	EventBus.cmd_send.emit(app_state.selected_ids,
		MessageBuilder.build_auto_push_goto(real.x, real.y))

	# 通知高亮
	EventBus.goto_issued.emit(real.x, real.y)
	get_viewport().set_input_as_handled()


func _execute_pending(_mb: InputEventMouseButton) -> void:
	if _pending_action != PendingAction.CIRCLE:
		return  # PATROL 等其它瞬态命令扩展点
	if app_state.selected_ids.is_empty():
		return
	var mouse_pos := get_global_mouse_position()
	var tile := CoordUtils.game_to_tile(mouse_pos)
	var real := CoordUtils.tile_to_real(tile.x, tile.y)
	EventBus.cmd_send.emit(app_state.selected_ids, MessageBuilder.build_auto_push_circle(real.x, real.y))
	EventBus.goto_issued.emit(real.x, real.y)  # 圆心高亮（复用 Goto 高亮框）
