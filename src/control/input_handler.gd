extends Node
## Presented by KeJi
## Created Date: 2026-08-02
## Modified Date: 2026-11-05
##
## ManualHandler — 手动控制：按住键集合 → (v, omega) → 变了才发（task_44 Step 3）
## 维护「当前按住的运动键」集合；按下/松开都重算 (v, omega)，与上次已发送值不同才发一帧；
## 集合为空 → (0, 0)。**不再**「任何一个键松开就停车」（旧 bug）。
## 量级：v = ±ProtocolDef.MANUAL_V_MAX、omega = ±ProtocolDef.MANUAL_OMEGA_MAX
##       （任务文档 §1.2 #11 定值，不做比例换算）；omega > 0 = 左转。
## 键位常量集中在本文件；量级定值只有 ProtocolDef 一处来源（MANUAL_V_MAX / MANUAL_OMEGA_MAX）。
## task_48 Step 4.7：X 键 = 对**选中的第一台**车随访（先发 msgid 8 切自动，再发 TASK_SET [{type:2}]）；
##   再按一次发**空 missions** 取消（Follow 是持续任务）。入口**先判焦点**：聊天框有焦点时
##   一个键都不处理（顺带修掉旧缺陷：在输入框里打字会触发运动）。

@export var app_state: AppStateResource

## 参与两轴合成的运动键（W/S 前后、A/D 左右转）
const MOTION_KEYS := [KEY_W, KEY_S, KEY_A, KEY_D]
## 事件类按键 → ProtocolDef.ACTION_*（task_44 §1.2 #3：事件 action 重排为 1..5）
const EVENT_KEYS := {KEY_E: ProtocolDef.ACTION_TAKEOFF, KEY_Q: ProtocolDef.ACTION_LAND}
## 随访键（task_48 Step 4.7）：按一下进入、再按一下取消
const FOLLOW_KEY := KEY_X

var _held: Dictionary = {}        # {keycode: int → true}  当前按住的运动键
var _last_sent := Vector2.ZERO    # 上一次**已发送**的 (v, omega)
## 当前随访的 vehicle_id（"" = 未随访）；**不复用** AppStateResource.Mode.FOLLOW
## （那是「相机跟车」，见 camera_2d.gd:62-64 —— 复用会把相机也带过去）
var _follow_vid: String = ""


## 纯函数：按键集合 → (v, omega)。只读入参，不碰任何成员状态（无头单测直接断言）。
## W/S 与 A/D 各自相消（同按 → 该轴 0）。
static func Input_To_Velocity(held: Dictionary) -> Vector2:
	var v := 0.0
	if held.has(KEY_W) and not held.has(KEY_S):
		v = ProtocolDef.MANUAL_V_MAX
	elif held.has(KEY_S) and not held.has(KEY_W):
		v = -ProtocolDef.MANUAL_V_MAX
	var omega := 0.0
	if held.has(KEY_A) and not held.has(KEY_D):
		omega = ProtocolDef.MANUAL_OMEGA_MAX
	elif held.has(KEY_D) and not held.has(KEY_A):
		omega = -ProtocolDef.MANUAL_OMEGA_MAX
	return Vector2(v, omega)


## 按下/松开一个键 → 更新集合并返回「要发的 (v, omega)」；与上次已发送值相同 → null。
## 返回 Variant（Vector2 或 null）：键状态真相与「有没有手动车可发」解耦，本函数不发帧。
func Apply_Key(keycode: int, pressed: bool) -> Variant:
	if pressed:
		_held[keycode] = true
	else:
		_held.erase(keycode)
	var now := Input_To_Velocity(_held)
	if now.is_equal_approx(_last_sent):
		return null
	_last_sent = now
	return now


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if key_event.echo:
		return

	# ⓪ 入口先判焦点（task_48 Step 4.7）：键盘焦点在输入框（LineEdit / 聊天框）时一律不处理，
	#    否则打 "x" / "w" 会触发随访或运动（旧缺陷）。
	if _Gui_Focus_Taken():
		return

	var kc := key_event.keycode

	# ⓪' X 键随访（task_48 Step 4.7）：放在事件键/运动键分支**之前**（X 与 E/Q/WASD 无冲突）
	if kc == FOLLOW_KEY:
		if key_event.pressed:
			_Toggle_Follow()
		get_viewport().set_input_as_handled()
		return

	# ① 事件类按键（E 起飞 / Q 降落）：只在按下时发一帧事件，不进运动集合
	if EVENT_KEYS.has(kc):
		if not key_event.pressed:
			return
		if app_state == null or app_state.manual_target.is_empty():
			return
		EventBus.cmd_send.emit([app_state.manual_target] as Array[String],
				MessageBuilder.build_manual_event(EVENT_KEYS[kc]))
		return

	# ② 运动键：Space 及其它键不再有任何绑定（停车 = 全零 8 B 运动帧）
	if not MOTION_KEYS.has(kc):
		return
	var vel: Variant = Apply_Key(kc, key_event.pressed)
	if not (vel is Vector2):
		return              # 值没变 → 不发帧
	if app_state == null or app_state.manual_target.is_empty():
		return              # 状态照记、不发送
	var v2: Vector2 = vel
	EventBus.cmd_send.emit([app_state.manual_target] as Array[String],
			MessageBuilder.build_manual_motion(v2.x, v2.y))


## X 键：进入 / 退出随访（task_48 Step 4.7）。
## 进入条件（三条全满足）：选中非空、`manual_target` 为空（手动优先）、当前**不是**相机跟车模式；
## 动作：**先**发 msgid 8（切自动，否则车端 Auto 分支不生效），**再**发 TASK_SET [{type:2, x:0, y:0}]；
## 退出：再按一次 → 发空 missions（mission_count = 0 是唯一取消入口；Follow 是持续任务，不取消不会自己结束）。
func _Toggle_Follow() -> void:
	if app_state == null:
		return
	# ① 退出优先：本节点记录着随访车 → 直接取消（不要求它仍被选中）
	if not _follow_vid.is_empty():
		EventBus.cmd_send.emit([_follow_vid] as Array[String], MessageBuilder.build_auto_cancel())
		EventBus.log_message.emit("🛑 随访取消（空 missions）→ %s" % _follow_vid, "info")
		print("[Input] 随访取消 → %s" % _follow_vid)
		_follow_vid = ""
		return
	# ② 进入条件
	if app_state.selected_ids.is_empty():
		print("[Input] X：未选中任何车 → 忽略")
		return
	if not app_state.manual_target.is_empty():
		print("[Input] X：手动目标 %s 占用中 → 忽略（手动优先）" % app_state.manual_target)
		return
	if app_state.mode == AppStateResource.Mode.FOLLOW:
		print("[Input] X：当前是相机跟车模式 → 忽略")
		return
	var vid := str(app_state.selected_ids[0])   # 只发**选中第一台**
	EventBus.cmd_send.emit([vid] as Array[String], MessageBuilder.build_mode_switch_auto())
	EventBus.cmd_send.emit([vid] as Array[String],
			MessageBuilder.build_task_set([{"type": ProtocolDef.MISSION_TYPE_FOLLOW, "x": 0.0, "y": 0.0}]))
	_follow_vid = vid
	print("[Input] 随访开始 → %s（已先发 msgid 8 切自动）" % vid)
	EventBus.follow_requested.emit(vid)          # UI 侧补一行 detector 提示（见 auto_handler）


## 是否有 GUI 控件（LineEdit / 聊天框）持有焦点 —— 有则本帧所有按键都不处理。
## `-s` 单测 / 未入树时 `get_viewport()` 为 null → 视为无焦点（不 panic）。
func _Gui_Focus_Taken() -> bool:
	if not is_inside_tree():
		return false
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() != null
