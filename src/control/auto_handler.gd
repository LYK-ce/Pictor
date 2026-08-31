extends Node2D
## Presented by KeJi
## Date: 2026-08-05
##
## AutoHandler — 自动控制编排：
## 1. 右键 Goto 广播给 selected_ids（原有）
## 2. LLM 指令编排：监听 EventBus.command_requested → 拼车辆上下文 → 调 util.llm.generate_cmds
##    → 接收 cmds_generated → 按车分发（Task 27）
## 瞬态态：点命令按钮（如巡逻）后等待目标点，左键执行 / 右键取消

@export var app_state: AppStateResource

## 工具箱引用（运行时获取，Main/Util）
@onready var util := get_node("../../Util") as Util
## 车辆注册表（运行时获取，Main/VehicleRegistry；拼 LLM 上下文 + 车名→id 映射）
@onready var vehicle_registry := get_node("../../VehicleRegistry") as VehicleRegistry

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


## 收到 TextInput/STT 等输入源的指令请求 → 拼车辆上下文 → 调 LLM 翻译
func _on_command_requested(text: String) -> void:
	if util == null or util.llm == null:
		printerr("[AutoHandler] util/llm 不可用")
		return
	util.llm.generate_cmds(_build_context(text))


## 从车辆注册表拼「车辆列表 + 用户指令」上下文
func _build_context(user_text: String) -> String:
	var lines := PackedStringArray()
	lines.append("当前在线车辆：")
	if vehicle_registry == null or vehicle_registry.vehicles.is_empty():
		lines.append("（无）")
	else:
		for id: String in vehicle_registry.vehicles:
			var v: Dictionary = vehicle_registry.vehicles[id]
			lines.append("- %s，位置 (%.1f, %.1f)" % [
				str(v.get("name", id)), float(v.get("x", 0.0)), float(v.get("y", 0.0))])
	lines.append("")
	lines.append("用户指令：" + user_text)
	return "\n".join(lines)


## LLM 翻译成功 → 按车分发（Task 27：mock 阶段先打印，后续改 cmd_send 逐条下发）
func _on_cmds_generated(cmds: Array) -> void:
	if cmds.is_empty():
		print("[AutoHandler] LLM 无有效指令")
		return
	for cmd in cmds:
		if not cmd is Dictionary:
			continue
		var vehicle_name: String = str(cmd.get("vehicle", ""))
		var vehicle_id := ""
		if vehicle_registry:
			vehicle_id = vehicle_registry.get_id_by_name(vehicle_name)
		print("[LLM] → %s (%s): %s(%.1f, %.1f)" % [
			vehicle_name, vehicle_id,
			str(cmd.get("type", "")),
			float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0))])


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
