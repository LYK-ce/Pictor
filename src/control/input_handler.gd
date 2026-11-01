extends Node
## Presented by KeJi
## Created Date: 2026-08-02
## Modified Date: 2026-11-01
##
## ManualHandler — 手动控制：按住键集合 → (v, omega) → 变了才发（task_44 Step 3）
## 维护「当前按住的运动键」集合；按下/松开都重算 (v, omega)，与上次已发送值不同才发一帧；
## 集合为空 → (0, 0)。**不再**「任何一个键松开就停车」（旧 bug）。
## 量级：v = ±ProtocolDef.MANUAL_V_MAX、omega = ±ProtocolDef.MANUAL_OMEGA_MAX
##       （任务文档 §1.2 #11 定值，不做比例换算）；omega > 0 = 左转。
## 键位常量集中在本文件；量级定值只有 ProtocolDef 一处来源（MANUAL_V_MAX / MANUAL_OMEGA_MAX）。

@export var app_state: AppStateResource

## 参与两轴合成的运动键（W/S 前后、A/D 左右转）
const MOTION_KEYS := [KEY_W, KEY_S, KEY_A, KEY_D]
## 事件类按键 → ProtocolDef.ACTION_*（task_44 §1.2 #3：事件 action 重排为 1..5）
const EVENT_KEYS := {KEY_E: ProtocolDef.ACTION_TAKEOFF, KEY_Q: ProtocolDef.ACTION_LAND}

var _held: Dictionary = {}        # {keycode: int → true}  当前按住的运动键
var _last_sent := Vector2.ZERO    # 上一次**已发送**的 (v, omega)


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

	# ① 事件类按键（E 起飞 / Q 降落）：只在按下时发一帧事件，不进运动集合
	var kc := key_event.keycode
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
