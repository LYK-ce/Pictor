extends SceneTree

## Presented by KeJi
## Created Date ： 2026-08-11
## Modified Date ： 2026-11-05
##
## Orion 协议 v2 编解码 roundtrip 测试（headless）
## 用法: godot --headless --path <项目> -s <本脚本路径>
## 覆盖：帧/消息 roundtrip（v2 变长 sysid）+ 大端字节序断言（与 Rust 端字节比对）
## Task 21：地图改 log-odds 语义（delta i8 位模式 / clamp / 阈值派生边界）
## task_40 Step 4：Follow(type=2) 放开（`_test_follow_task_set`）
## task_41 Step 1：Containment(type=3) + TASK_SET **按 type 变长**（0/2 = 9B、3 = 13B），
##                 ∉{0,2,3,4,5} 由 Encode 报错并**返回空数组（不发帧）**，不再降级成 Goto
## task_44 Step 3：msgid 4 改 8B 运动 / 3B 事件、msgid 8 模式帧、WASD 两轴纯函数
## task_48 Step 4：Face(type=4, 9B) / Guard(type=5, 17B) 金标 + 往返 + 长度表；未知 type 仍拒发
##
## ⚠️ 入口必须是 `_initialize`（不是 `_init`）：`_init` 阶段 autoload（EventBus）尚未注册，
##    `load("res://src/control/input_handler.gd")` 会编译失败（Identifier not found: EventBus）。
##    同理，本文件**不能 preload** 含 EventBus 的脚本，只能在 `_initialize` 里运行期 load()。

func _initialize() -> void:
	var ok := true
	ok = ok and _test_frame()
	ok = ok and _test_pose()
	ok = ok and _test_map_full()
	ok = ok and _test_map_delta()
	ok = ok and _test_manual_control()
	ok = ok and _test_takeoff_land()
	ok = ok and _test_mode()
	ok = ok and _test_input_velocity()
	ok = ok and _test_task_set()
	ok = ok and _test_build_cmd()
	ok = ok and _test_parser_dispatch()
	ok = ok and _test_endianness()
	ok = ok and _test_llm_missions()
	ok = ok and _test_circle_task_set()
	ok = ok and _test_follow_task_set()
	ok = ok and _test_containment_task_set()
	ok = ok and _test_face_task_set()
	ok = ok and _test_guard_task_set()
	ok = ok and _test_assist_request()
	ok = ok and _test_target_alloc()
	ok = ok and _test_log_odds_signed()
	ok = ok and _test_clamp()
	ok = ok and _test_threshold()
	ok = ok and _test_build_cmd_map_full()
	ok = ok and _test_return_frame_size()
	ok = ok and _test_map_accumulator()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


func _test_frame() -> bool:
	# 带 1B sysid（模拟非空身份）验证变长帧头
	var payload := PackedByteArray([1, 2, 3, 4, 5])
	var frame := OrionFrame.Encode_Frame(3, PackedByteArray([200]), 1, payload)
	if frame[0] != 0x4F:
		print("FAIL magic"); return false
	# len 字段大端：5 → [00 00 00 05]
	if frame[1] != 0x00 or frame[2] != 0x00 or frame[3] != 0x00 or frame[4] != 0x05:
		print("FAIL len BE: ", frame.slice(1, 5)); return false
	# v2：offset 6 = sysid_len（=1），sysid 字节在 7，compid 在 8
	if frame[6] != 1:
		print("FAIL sysid_len"); return false
	if frame[7] != 200:
		print("FAIL sysid byte"); return false
	if frame[8] != 1:
		print("FAIL compid"); return false
	# msgid 大端：3 → [00 03] @9-10（sysid_len=1）
	if frame[9] != 0x00 or frame[10] != 0x03:
		print("FAIL msgid BE: ", frame.slice(9, 11)); return false
	# payload 从 11 开始
	if frame[11] != 1:
		print("FAIL payload start"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	if not dec.ok:
		print("FAIL decode: ", dec.error); return false
	if dec.msgid != 3 or dec.sysid != PackedByteArray([200]) or dec.compid != 1 or dec.payload != payload:
		print("FAIL fields: ", dec); return false
	# 错误路径
	if OrionFrame.Decode_Frame(PackedByteArray([0x50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])).ok:
		print("FAIL bad magic accepted"); return false
	if OrionFrame.Decode_Frame(frame.slice(0, 10)).ok:
		print("FAIL truncated accepted"); return false
	print("PASS frame"); return true


func _test_pose() -> bool:
	# v4：38B，含 z 高度 + rtk_fixed + valid/sub_gx/sub_gy 意图字段
	var payload := OrionMessages.Encode_Pose(12345, 1.5, -2.25, 0.1, -0.2, 0.785, true, 10, -20, 3.5, true)
	if payload.size() != 38:
		print("FAIL pose size: ", payload.size()); return false
	var dec := OrionMessages.Decode_Pose(payload)
	if not dec.ok:
		print("FAIL pose decode: ", dec.error); return false
	if dec.time_boot_ms != 12345 or absf(dec.x - 1.5) > 0.0001 or absf(dec.y - (-2.25)) > 0.0001:
		print("FAIL pose fields: ", dec); return false
	if absf(dec.z - 3.5) > 0.0001:
		print("FAIL pose z field: ", dec); return false
	if absf(dec.vx - 0.1) > 0.0001 or absf(dec.vy - (-0.2)) > 0.0001 or absf(dec.yaw - 0.785) > 0.0001:
		print("FAIL pose fields2: ", dec); return false
	if dec.valid != true or dec.sub_gx != 10 or dec.sub_gy != -20:
		print("FAIL pose intent fields: ", dec); return false
	if dec.rtk_fixed != true:
		print("FAIL pose rtk_fixed field: ", dec); return false
	# 37B 旧帧应被拒绝（v4 严格校验 38B，对齐 Rust）
	var old_payload := OrionMessages.Encode_Pose(0, 0, 0, 0, 0, 0)
	if OrionMessages.Decode_Pose(old_payload.slice(0, 37)).ok:
		print("FAIL 37B old pose accepted"); return false
	print("PASS pose"); return true


func _test_map_full() -> bool:
	# Task 21：data = log-odds i8 位模式（pattern [0, 8, -8, 3]）
	var data := PackedByteArray()
	data.resize(256 * 256)
	var pattern := [0, 8, -8, 3]
	for i in range(data.size()):
		data[i] = pattern[i % 4] & 0xFF
	var payload := OrionMessages.Encode_Map_Full(999, -256, 256, 256, 256, 0.5, data)
	if payload.size() != 20 + 65536:
		print("FAIL map_full size: ", payload.size()); return false
	var dec := OrionMessages.Decode_Map_Full(payload)
	if not dec.ok:
		print("FAIL map_full decode: ", dec.error); return false
	if dec.origin_gx != -256 or dec.origin_gy != 256 or dec.width != 256 or dec.height != 256:
		print("FAIL map_full header: ", dec); return false
	if absf(dec.resolution - 0.5) > 0.0001 or dec.data.size() != 65536:
		print("FAIL map_full meta"); return false
	# data[3]=3, data[4]=0, data[5]=8（pattern 0,8,248,3 的位模式）
	if dec.data[3] != 3 or dec.data[4] != 0 or dec.data[5] != 8:
		print("FAIL map_full data: ", [dec.data[3], dec.data[4], dec.data[5]]); return false
	print("PASS map_full"); return true


func _test_map_delta() -> bool:
	# Task 21：delta i8 差分（负值位模式 + 聚合净变化超 ±8 场景）
	var entries := [
		{"gx": -1, "gy": 2, "delta": -8},
		{"gx": 300, "gy": -400, "delta": 15},
		{"gx": 1, "gy": 1, "delta": -1},
	]
	var payload := OrionMessages.Encode_Map_Delta(777, entries)
	if payload.size() != 6 + 27:
		print("FAIL map_delta size: ", payload.size()); return false
	var dec := OrionMessages.Decode_Map_Delta(payload)
	if not dec.ok:
		print("FAIL map_delta decode: ", dec.error); return false
	if dec.count != 3 or dec.entries.size() != 3:
		print("FAIL map_delta count"); return false
	var e0: Dictionary = dec.entries[0]
	var e1: Dictionary = dec.entries[1]
	var e2: Dictionary = dec.entries[2]
	if e0.gx != -1 or e0.gy != 2 or e0.delta != -8:
		print("FAIL map_delta e0: ", e0); return false
	if e1.gx != 300 or e1.gy != -400 or e1.delta != 15:
		print("FAIL map_delta e1: ", e1); return false
	if e2.delta != -1:
		print("FAIL map_delta e2: ", e2); return false
	# 位模式断言：-8 → 0xF8（entry0 delta @14）、15 → 0x0F（entry1 delta @23）、-1 → 0xFF（entry2 delta @32）
	if payload[14] != 0xF8:
		print("FAIL delta -8 byte: ", payload[14]); return false
	if payload[23] != 0x0F:
		print("FAIL delta 15 byte: ", payload[23]); return false
	if payload[32] != 0xFF:
		print("FAIL delta -1 byte: ", payload[32]); return false
	print("PASS map_delta"); return true


func _test_manual_control() -> bool:
	# task_44 §1.2 #3：msgid 4 按长度分流（8B 运动 / 3B 事件），其余长度整帧拒
	# —— 8B 运动：Step 1 的字节金标（与 Rust `messages.rs` 同一串）——
	if OrionMessages.Encode_Manual_Motion(0.5, 0.0).hex_encode() != "3f00000000000000":
		print("FAIL manual motion golden1: ", OrionMessages.Encode_Manual_Motion(0.5, 0.0).hex_encode()); return false
	if OrionMessages.Encode_Manual_Motion(0.0, 0.0).hex_encode() != "0000000000000000":
		print("FAIL manual motion golden2: ", OrionMessages.Encode_Manual_Motion(0.0, 0.0).hex_encode()); return false
	if OrionMessages.Encode_Manual_Motion(0.0, -0.5).hex_encode() != "00000000bf000000":
		print("FAIL manual motion golden3: ", OrionMessages.Encode_Manual_Motion(0.0, -0.5).hex_encode()); return false
	# —— 8B 运动：§1.2 #11 定值（v=0.45、|omega|=0.5）——
	var g_w := OrionMessages.Encode_Manual_Motion(0.45, 0.0)
	if g_w.hex_encode() != "3ee6666600000000":
		print("FAIL manual motion W golden: ", g_w.hex_encode()); return false
	var g_wa := OrionMessages.Encode_Manual_Motion(0.45, 0.5)
	if g_wa.hex_encode() != "3ee666663f000000":
		print("FAIL manual motion W+A golden: ", g_wa.hex_encode()); return false
	if OrionMessages.Encode_Manual_Motion(-0.45, 0.0).hex_encode() != "bee6666600000000":
		print("FAIL manual motion S golden"); return false
	if g_wa.size() != 8:
		print("FAIL manual motion size: ", g_wa.size()); return false
	# —— 8B roundtrip → kind = "motion" ——
	var dec := OrionMessages.Decode_Manual_Control(OrionMessages.Encode_Manual_Motion(0.45, -0.5))
	if not dec.ok or dec.kind != "motion":
		print("FAIL manual motion decode: ", dec); return false
	if absf(dec.v - 0.45) > 1e-6 or absf(dec.omega + 0.5) > 1e-6:
		print("FAIL manual motion decode fields: ", dec); return false
	# —— 3B 事件：action u8 + param i16 BE ——
	var ev := OrionMessages.Encode_Manual_Event(ProtocolDef.ACTION_BEEP, -50)
	if ev.size() != 3:
		print("FAIL manual event size: ", ev.size()); return false
	if ev[0] != 1 or ev.slice(1, 3) != PackedByteArray([0xFF, 0xCE]):
		print("FAIL manual event bytes: ", ev); return false
	var dec_ev := OrionMessages.Decode_Manual_Control(ev)
	if not dec_ev.ok or dec_ev.kind != "event" or dec_ev.action != 1 or dec_ev.param != -50:
		print("FAIL manual event decode: ", dec_ev); return false
	# 编码门控：未知 action（9 = 已删的模式切换 action）→ 空数组（不发帧）
	if not OrionMessages.Encode_Manual_Event(9, 0).is_empty():
		print("FAIL manual event unknown action accepted"); return false
	if not OrionMessages.Encode_Manual_Event(0, 0).is_empty():
		print("FAIL manual event action 0 accepted（旧 FORWARD 已删）"); return false
	# 解码门控：3B 里的非法 action → 整帧拒
	if OrionMessages.Decode_Manual_Control(PackedByteArray([9, 0, 0])).ok:
		print("FAIL manual event decode unknown action accepted"); return false
	# —— 非法长度整帧拒（8/3 之外的 0/1/2/4/7/9）——
	for n in [0, 1, 2, 4, 7, 9]:
		var bad := PackedByteArray()
		bad.resize(n)
		if OrionMessages.Decode_Manual_Control(bad).ok:
			print("FAIL manual control bad size ", n, " accepted"); return false
	print("PASS manual_control"); return true


# ─── task_44 Step 3：msgid 8 模式帧（1 B：0 手动 / 1 自动）────────
func _test_mode() -> bool:
	if OrionMessages.Encode_Mode(ProtocolDef.MODE_MANUAL).hex_encode() != "00":
		print("FAIL mode manual golden: ", OrionMessages.Encode_Mode(0).hex_encode()); return false
	if OrionMessages.Encode_Mode(ProtocolDef.MODE_AUTO).hex_encode() != "01":
		print("FAIL mode auto golden: ", OrionMessages.Encode_Mode(1).hex_encode()); return false
	# roundtrip
	var dec := OrionMessages.Decode_Mode(OrionMessages.Encode_Mode(ProtocolDef.MODE_AUTO))
	if not dec.ok or dec.mode != 1:
		print("FAIL mode roundtrip: ", dec); return false
	# 非法值 / 非法长度 → 解码整帧拒
	if OrionMessages.Decode_Mode(PackedByteArray([2])).ok:
		print("FAIL mode invalid value accepted"); return false
	if OrionMessages.Decode_Mode(PackedByteArray()).ok:
		print("FAIL mode empty payload accepted"); return false
	if OrionMessages.Decode_Mode(PackedByteArray([0, 1])).ok:
		print("FAIL mode 2B payload accepted"); return false
	# 编码门控：非法值 → 空数组（不发帧）
	if not OrionMessages.Encode_Mode(7).is_empty():
		print("FAIL mode encode invalid accepted"); return false
	# Build_Cmd 走 msgid 8（整帧 = Step 1 金标）
	var frame_auto := OrionMessages.Build_Cmd(MessageBuilder.build_mode_switch_auto())
	if frame_auto.hex_encode() != "4f000000010000c80008010000":
		print("FAIL mode auto frame golden: ", frame_auto.hex_encode()); return false
	var d_auto := OrionFrame.Decode_Frame(frame_auto)
	if not d_auto.ok or d_auto.msgid != 8 or not d_auto.sysid.is_empty() or d_auto.compid != 200:
		print("FAIL mode auto frame header: ", d_auto); return false
	if d_auto.payload.size() != 1 or d_auto.payload[0] != 1:
		print("FAIL mode auto frame payload: ", d_auto.payload); return false
	var d_manual := OrionFrame.Decode_Frame(OrionMessages.Build_Cmd(MessageBuilder.build_mode_switch_manual()))
	if not d_manual.ok or d_manual.msgid != 8 or d_manual.payload.size() != 1 or d_manual.payload[0] != 0:
		print("FAIL mode manual frame: ", d_manual); return false
	print("PASS mode"); return true


# ─── task_44 Step 3：WASD 两轴纯函数 + 键集合状态机（旧 bug 回归）──────
func _test_input_velocity() -> bool:
	# 运行期 load（不能 preload：编译期 EventBus 未注册，见文件头）
	var ih: Script = load("res://src/control/input_handler.gd")
	if ih == null:
		print("FAIL load input_handler.gd"); return false
	# ① 全松 → (0, 0)
	if not _vec_eq(ih.Input_To_Velocity({}), 0.0, 0.0):
		print("FAIL input velocity all released: ", ih.Input_To_Velocity({})); return false
	# ② W → (v_max, 0)
	if not _vec_eq(ih.Input_To_Velocity({KEY_W: true}), 0.45, 0.0):
		print("FAIL input velocity W: ", ih.Input_To_Velocity({KEY_W: true})); return false
	# ③ W+A → (v_max, +omega_max)；**左转为正**
	if not _vec_eq(ih.Input_To_Velocity({KEY_W: true, KEY_A: true}), 0.45, 0.5):
		print("FAIL input velocity W+A（左转应为正）: ", ih.Input_To_Velocity({KEY_W: true, KEY_A: true})); return false
	# ④ 单键表（§1.4 手动行）
	if not _vec_eq(ih.Input_To_Velocity({KEY_A: true}), 0.0, 0.5):
		print("FAIL input velocity A"); return false
	if not _vec_eq(ih.Input_To_Velocity({KEY_S: true}), -0.45, 0.0):
		print("FAIL input velocity S"); return false
	if not _vec_eq(ih.Input_To_Velocity({KEY_D: true}), 0.0, -0.5):
		print("FAIL input velocity D"); return false
	# ⑤ 相消：W+S → v=0；A+D → omega=0
	if not _vec_eq(ih.Input_To_Velocity({KEY_W: true, KEY_S: true}), 0.0, 0.0):
		print("FAIL input velocity W+S cancel"); return false
	if not _vec_eq(ih.Input_To_Velocity({KEY_A: true, KEY_D: true}), 0.0, 0.0):
		print("FAIL input velocity A+D cancel"); return false
	# ⑥ 状态机（旧 bug 回归）：松开 A 必须**保留** W，不是 (0,0)
	var h: Node = ih.new()
	if h == null:
		print("FAIL input_handler new()"); return false
	if not _vec_eq(h.Apply_Key(KEY_W, true), 0.45, 0.0):
		print("FAIL state W"); return false
	if not _vec_eq(h.Apply_Key(KEY_A, true), 0.45, 0.5):
		print("FAIL state W+A"); return false
	if not _vec_eq(h.Apply_Key(KEY_A, false), 0.45, 0.0):
		print("FAIL state release A should keep W (0.45,0)，旧 bug 是 (0,0)"); return false
	if not _vec_eq(h.Apply_Key(KEY_W, false), 0.0, 0.0):
		print("FAIL state release W → (0,0)"); return false
	h.free()
	# ⑦ 去重：同一状态连按两次，第二次返回 null（不发帧）
	var h2: Node = ih.new()
	if not (h2.Apply_Key(KEY_W, true) is Vector2):
		print("FAIL dedupe first send"); return false
	if h2.Apply_Key(KEY_W, true) != null:
		print("FAIL dedupe second send should be null"); return false
	h2.free()
	# ⑧ Space 不再产生停车帧（协议已无 stop action）
	var h3: Node = ih.new()
	if h3.Apply_Key(KEY_SPACE, false) != null:
		print("FAIL space should not send"); return false
	h3.free()
	print("PASS input_velocity"); return true


func _vec_eq(v: Vector2, want_v: float, want_omega: float) -> bool:
	return absf(v.x - want_v) <= 1e-6 and absf(v.y - want_omega) <= 1e-6


# ─── task_44 §1.2 #3：事件类动作（起飞/降落）—————————————
func _test_takeoff_land() -> bool:
	if ProtocolDef.ACTION_TAKEOFF != 4 or ProtocolDef.ACTION_LAND != 5:
		print("FAIL takeoff/land const value"); return false
	var takeoff := MessageBuilder.build_manual_event(ProtocolDef.ACTION_TAKEOFF)
	if takeoff.action != ProtocolDef.ACTION_TAKEOFF:
		print("FAIL takeoff action: ", takeoff); return false
	var land := MessageBuilder.build_manual_event(ProtocolDef.ACTION_LAND)
	if land.action != ProtocolDef.ACTION_LAND:
		print("FAIL land action: ", land); return false
	var payload := OrionMessages.Encode_Manual_Event(ProtocolDef.ACTION_TAKEOFF, 0)
	if payload.size() != 3 or payload[0] != 4:
		print("FAIL takeoff payload: ", payload); return false
	var dec := OrionMessages.Decode_Manual_Control(payload)
	if not dec.ok or dec.kind != "event" or dec.action != 4 or dec.param != 0:
		print("FAIL takeoff roundtrip: ", dec); return false
	var payload2 := OrionMessages.Encode_Manual_Event(ProtocolDef.ACTION_LAND, 0)
	var dec2 := OrionMessages.Decode_Manual_Control(payload2)
	if not dec2.ok or dec2.action != 5:
		print("FAIL land roundtrip: ", dec2); return false
	# 事件帧走 Build_Cmd（msgid 4、payload 3 B）
	var frame := OrionMessages.Build_Cmd(takeoff)
	var d_frame := OrionFrame.Decode_Frame(frame)
	if not d_frame.ok or d_frame.msgid != 4 or d_frame.payload.size() != 3:
		print("FAIL takeoff frame: ", d_frame); return false
	print("PASS takeoff_land"); return true


func _test_task_set() -> bool:
	# —— 单车（mission_count=1；task_36 新布局 1 + 9n，无成员段）——
	var payload := OrionMessages.Encode_Task_Set([{"type": 0, "x": 12.5, "y": -3.25}])
	# 布局: [m_count=1][type=0][x 4B][y 4B] = 1 + 9 = 10B
	if payload.size() != 10:
		print("FAIL task_set size: ", payload.size()); return false
	if payload[0] != 1 or payload[1] != 0:
		print("FAIL task_set header bytes"); return false
	if payload.slice(2, 6) != PackedByteArray([0x41, 0x48, 0x00, 0x00]):
		print("FAIL task_set x=12.5 BE: ", payload.slice(2, 6)); return false
	if payload.slice(6, 10) != PackedByteArray([0xC0, 0x50, 0x00, 0x00]):
		print("FAIL task_set y=-3.25 BE: ", payload.slice(6, 10)); return false
	var dec := OrionMessages.Decode_Task_Set(payload)
	if not dec.ok or dec.mission_count != 1 or dec.missions.size() != 1:
		print("FAIL task_set decode: ", dec); return false
	if dec.has("member_count") or dec.has("members"):
		print("FAIL task_set still returns member fields: ", dec); return false
	var m0: Dictionary = dec.missions[0]
	if m0.type != 0 or absf(m0.x - 12.5) > 0.0001 or absf(m0.y - (-3.25)) > 0.0001:
		print("FAIL task_set m0: ", m0); return false

	# —— 多条任务（mission_count=3）往返 ——
	var missions := [
		{"type": 0, "x": 12.5, "y": -3.25},
		{"type": 0, "x": 0.0, "y": 99.99},
		{"type": 0, "x": -1.0, "y": 1.0},
	]
	var payload2 := OrionMessages.Encode_Task_Set(missions)
	if payload2.size() != 1 + 9 * 3:
		print("FAIL task_set multi size: ", payload2.size()); return false
	if payload2[0] != 3:
		print("FAIL task_set multi count byte"); return false
	var dec2 := OrionMessages.Decode_Task_Set(payload2)
	if not dec2.ok or dec2.mission_count != 3 or dec2.missions.size() != 3:
		print("FAIL task_set multi decode: ", dec2); return false
	if absf(dec2.missions[1].y - 99.99) > 0.0001 or absf(dec2.missions[2].x - (-1.0)) > 0.0001:
		print("FAIL task_set multi missions: ", dec2.missions); return false

	# —— 取消帧（mission_count=0 → 1 字节）——
	var cancel := OrionMessages.Encode_Task_Set([])
	if cancel.size() != 1 or cancel[0] != 0:
		print("FAIL task_set cancel layout"); return false
	var dec_cancel := OrionMessages.Decode_Task_Set(cancel)
	if not dec_cancel.ok or dec_cancel.mission_count != 0 or not dec_cancel.missions.is_empty():
		print("FAIL task_set cancel decode: ", dec_cancel); return false
	# 空 payload 不是取消帧（车端 decode_task_set 也拒）
	if OrionMessages.Decode_Task_Set(PackedByteArray()).ok:
		print("FAIL empty payload accepted"); return false

	# —— 旧布局（带 member 段）必须被拒：长度 1+9n 不符 ——
	var old_layout := PackedByteArray([1, 1, 2, 0x10, 0x20])
	old_layout.append_array(OrionMessages.Encode_Task_Set([{"type": 0, "x": 12.5, "y": -3.25}]).slice(1))
	if old_layout.size() != 14 or OrionMessages.Decode_Task_Set(old_layout).ok:
		print("FAIL legacy layout with peer list accepted"); return false

	# —— 长度不符：mission_count=1 但只有 8B 任务数据 / 多 1 字节 ——
	var short_payload := PackedByteArray([1])
	short_payload.resize(9)
	if OrionMessages.Decode_Task_Set(short_payload).ok:
		print("FAIL task_set short payload accepted"); return false
	var long_payload := payload.duplicate()
	long_payload.append(0)
	if OrionMessages.Decode_Task_Set(long_payload).ok:
		print("FAIL task_set trailing byte accepted"); return false
	print("PASS task_set"); return true


func _test_build_cmd() -> bool:
	# task_44 §1.2 #11：手动量级定值 v=0.45、|omega|=0.5（W+A）
	var cmd := MessageBuilder.build_manual_motion(0.45, 0.5)
	var frame := OrionMessages.Build_Cmd(cmd)
	if frame.is_empty():
		print("FAIL build_cmd empty"); return false
	# 整帧金标：空 sysid（sysid_len=0）+ compid=200 + msgid 4 + 8B payload + checksum 0
	if frame.hex_encode() != "4f000000080000c800043ee666663f0000000000":
		print("FAIL build_cmd W+A frame golden: ", frame.hex_encode()); return false
	var dec := OrionFrame.Decode_Frame(frame)
	# v2 终端上行：空 sysid（sysid_len=0）+ compid=200
	if not dec.ok or dec.msgid != 4 or not dec.sysid.is_empty() or dec.compid != 200:
		print("FAIL build_cmd frame: ", dec); return false
	var mc := OrionMessages.Decode_Manual_Control(dec.payload)
	if not mc.ok or mc.kind != "motion":
		print("FAIL build_cmd payload kind: ", mc); return false
	if absf(mc.v - 0.45) > 1e-6 or absf(mc.omega - 0.5) > 1e-6:
		print("FAIL build_cmd payload: ", mc); return false

	# 模式切换走 msgid 8（task_44 §1.2 #4）
	var frame_mode := OrionMessages.Build_Cmd(MessageBuilder.build_mode_switch_auto())
	if frame_mode.hex_encode() != "4f000000010000c80008010000":
		print("FAIL build_cmd mode frame golden: ", frame_mode.hex_encode()); return false
	var dec_mode := OrionFrame.Decode_Frame(frame_mode)
	if not dec_mode.ok or dec_mode.msgid != 8 or dec_mode.payload.size() != 1 or dec_mode.payload[0] != 1:
		print("FAIL build_cmd mode frame: ", dec_mode); return false

	var cancel := MessageBuilder.build_auto_cancel()
	var frame2 := OrionMessages.Build_Cmd(cancel)
	var dec2 := OrionFrame.Decode_Frame(frame2)
	var ts := OrionMessages.Decode_Task_Set(dec2.payload)
	if ts.mission_count != 0 or not ts.missions.is_empty():
		print("FAIL build_cmd cancel: ", ts); return false
	print("PASS build_cmd"); return true


func _test_parser_dispatch() -> bool:
	# pose 帧 → parse_orion_frame（带 1B sysid 模拟车身份）
	var pose_frame := OrionFrame.Encode_Frame(1, PackedByteArray([1]), 1, OrionMessages.Encode_Pose(1, 2.0, 3.0, 0, 0, 0))
	var r := MessageParser.parse_orion_frame(pose_frame)
	if not r.ok or r.msgid != 1 or absf(r.data.x - 2.0) > 0.0001:
		print("FAIL parser pose: ", r); return false
	if r.data.rtk_fixed != false:
		print("FAIL parser pose rtk_fixed: ", r); return false
	# map_full 帧 → chunk 坐标换算（origin=-256 → chunk_x=-1）
	var data := PackedByteArray(); data.resize(65536)
	var full_frame := OrionFrame.Encode_Frame(2, PackedByteArray([1]), 1, OrionMessages.Encode_Map_Full(0, -256, 256, 256, 256, 0.5, data))
	var r2 := MessageParser.parse_orion_frame(full_frame)
	if not r2.ok or r2.data.chunk_x != -1 or r2.data.chunk_y != 1:
		print("FAIL parser map_full chunk: ", r2); return false
	# 未知 msgid
	var bad := OrionFrame.Encode_Frame(99, PackedByteArray([1]), 1, PackedByteArray([0]))
	if MessageParser.parse_orion_frame(bad).ok:
		print("FAIL parser unknown msgid accepted"); return false
	# msgid 8（模式帧）→ data.mode（task_44 §1.2 #4）
	var mode_frame := OrionFrame.Encode_Frame(8, PackedByteArray([1]), 1, OrionMessages.Encode_Mode(ProtocolDef.MODE_AUTO))
	var r3 := MessageParser.parse_orion_frame(mode_frame)
	if not r3.ok or r3.msgid != 8 or r3.data.mode != 1:
		print("FAIL parser mode: ", r3); return false
	print("PASS parser_dispatch"); return true


func _test_llm_missions() -> bool:
	# LLM 输出任务序列（JSON 数组文本解析后）：字符串 type "goto" → 归一化 0
	# 所有任务合并为一条 TASK_SET，一次编码下发
	var missions := [
		{"type": "goto", "x": 3.0, "y": 5.0},
		{"type": "goto", "x": 1.0, "y": 1.0},
	]
	var task_set := MessageBuilder.build_task_set(missions)
	if task_set.msgid != ProtocolDef.MSGID_TASK_SET:
		print("FAIL build_task_set msgid"); return false
	var frame := OrionMessages.Build_Cmd(task_set)
	if frame.is_empty():
		print("FAIL missions frame empty"); return false
	var dec: Dictionary = OrionFrame.Decode_Frame(frame)
	var ts := OrionMessages.Decode_Task_Set(dec.payload)
	if ts.mission_count != 2 or ts.missions.size() != 2:
		print("FAIL missions count: ", ts); return false
	if ts.missions[0].type != 0 or absf(ts.missions[0].x - 3.0) > 0.0001 or absf(ts.missions[0].y - 5.0) > 0.0001:
		print("FAIL mission0: ", ts.missions[0]); return false
	if ts.missions[1].type != 0 or absf(ts.missions[1].x - 1.0) > 0.0001 or absf(ts.missions[1].y - 1.0) > 0.0001:
		print("FAIL mission1: ", ts.missions[1]); return false
	# 与 Rust 端字节比对：missions[0] = (type 0, x=3.0, y=5.0)；task_36 布局 1 + 9n，无成员段
	# payload: [mission_count=2] | 00 40 40 00 40 A0 00 00 | 00 3F 80 00 00 3F 80 00 00
	var payload: PackedByteArray = dec.payload
	if payload.size() != 1 + 9 * 2 or payload[0] != 2:
		print("FAIL missions count bytes"); return false
	if payload.slice(1, 2) != PackedByteArray([0x00]):
		print("FAIL mission0 type byte"); return false
	if payload.slice(2, 6) != PackedByteArray([0x40, 0x40, 0x00, 0x00]):
		print("FAIL mission0 x=3.0 BE: ", payload.slice(2, 6)); return false
	print("PASS llm_missions"); return true


# ─── Circle 已废弃（task_36 §十一 #27）：Pictor 不再生成 type=1 ────────

func _test_circle_task_set() -> bool:
	# 归一化：字符串 type 一律 → Goto（"circle" 的环形几何由地面站 TargetAlloc 算，不进协议）
	if ProtocolDef.Mission_Type_From("circle") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from circle should be Goto"); return false
	if ProtocolDef.Mission_Type_From("CIRCLE") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from CIRCLE case"); return false
	if ProtocolDef.Mission_Type_From("goto") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from goto"); return false
	if ProtocolDef.Mission_Type_From("unknown") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from unknown"); return false
	# 数字直通：1 原样返回；是否真的发出去由 Encode 的降级门控决定
	if ProtocolDef.Mission_Type_From(1) != 1:
		print("FAIL mission_type_from int passthrough"); return false

	# Encode 门控（task_41 §3.2 起**不再降级**）：整数 type=1（退役 Circle）→ printerr + 空数组
	var payload_int := OrionMessages.Encode_Task_Set([{"type": 1, "x": 3.0, "y": 4.0}])
	if not payload_int.is_empty():
		print("FAIL retired circle type=1 must not encode: ", payload_int); return false

	# build_task_set 字符串 "circle" 归一化（LLM 链路）→ Goto，且 1 + 9n 可编码
	var ms := MessageBuilder.build_task_set([{"type": "circle", "x": 3.0, "y": 4.0}])
	if ms.missions[0].type != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL build_task_set circle normalize"); return false
	var frame := OrionMessages.Build_Cmd(ms)
	var dec_frame := OrionFrame.Decode_Frame(frame)
	var ts := OrionMessages.Decode_Task_Set(dec_frame.payload)
	if not ts.ok or ts.mission_count != 1 or ts.missions.size() != 1:
		print("FAIL circle-as-goto roundtrip: ", ts); return false
	if absf(ts.missions[0].x - 3.0) > 0.0001 or absf(ts.missions[0].y - 4.0) > 0.0001:
		print("FAIL circle-as-goto fields: ", ts.missions[0]); return false
	print("PASS circle_task_set"); return true


# ─── task_40 Step 4：Follow(type=2) 放开 + 未知类型仍被降级 ────────────────

func _test_follow_task_set() -> bool:
	# ① 常量 + 归一化（"follow" 认得出；"goto"/"circle"/未知 仍是 0）
	if ProtocolDef.MISSION_TYPE_FOLLOW != 2:
		print("FAIL MISSION_TYPE_FOLLOW != 2"); return false
	if ProtocolDef.Mission_Type_From("follow") != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL mission_type_from follow"); return false
	if ProtocolDef.Mission_Type_From("FOLLOW") != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL mission_type_from FOLLOW case"); return false
	if ProtocolDef.Mission_Type_From(" follow ") != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL mission_type_from follow trimmed"); return false
	if ProtocolDef.Mission_Type_From(2) != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL mission_type_from int 2 passthrough"); return false
	if ProtocolDef.Mission_Type_From("goto") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from goto"); return false
	if ProtocolDef.Mission_Type_From("circle") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from circle should be Goto"); return false
	if ProtocolDef.Mission_Type_From("unknown") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from unknown"); return false

	# ② Encode：单条 type=2、x=y=0 → 10B，金标 01020000000000000000（与 Python 侧同一枚）
	var p := OrionMessages.Encode_Task_Set([{"type": 2, "x": 0.0, "y": 0.0}])
	if p.size() != 10 or p[0] != 1:
		print("FAIL follow payload size/count: ", p); return false
	if p[1] != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL follow type byte: ", p[1]); return false
	if p.hex_encode() != "01020000000000000000":
		print("FAIL follow golden bytes: ", p.hex_encode()); return false

	# ③ x 仍是大端 f32：x=12.5 → [41 48 00 00] @2..6，且 byte[1] 仍是 2
	var p2 := OrionMessages.Encode_Task_Set([{"type": 2, "x": 12.5, "y": 0.0}])
	if p2[1] != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL follow x-case type byte"); return false
	if p2.slice(2, 6) != PackedByteArray([0x41, 0x48, 0x00, 0x00]):
		print("FAIL follow f32 BE: ", p2.slice(2, 6)); return false

	# ④ 整帧 roundtrip：Build_Cmd → Decode_Frame → Decode_Task_Set
	var frame_f := OrionMessages.Build_Cmd(
		MessageBuilder.build_task_set([{"type": "follow", "x": 3.0, "y": 4.0}]))
	var dec_f := OrionFrame.Decode_Frame(frame_f)
	if not dec_f.ok:
		print("FAIL follow frame decode: ", dec_f.error); return false
	var ts := OrionMessages.Decode_Task_Set(dec_f.payload)
	if not ts.ok or ts.mission_count != 1:
		print("FAIL follow roundtrip: ", ts); return false
	if ts.missions[0].type != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL follow roundtrip type: ", ts.missions[0]); return false
	if absf(ts.missions[0].x - 3.0) > 0.0001 or absf(ts.missions[0].y - 4.0) > 0.0001:
		print("FAIL follow roundtrip fields: ", ts.missions[0]); return false
	# 字符串链路：build_task_set 已归一化成整数 2
	if MessageBuilder.build_task_set([{"type": "follow"}]).missions[0].type != ProtocolDef.MISSION_TYPE_FOLLOW:
		print("FAIL build_task_set follow normalize"); return false

	# ⑤ 混合 [2, 0]：逐条保住自己的 type，布局仍是 1 + 9n
	var pm := OrionMessages.Encode_Task_Set([{"type": 2, "x": 0.0, "y": 0.0},
			{"type": 0, "x": 1.0, "y": 1.0}])
	if pm.size() != 19 or pm[0] != 2:
		print("FAIL mixed payload layout: ", pm); return false
	if pm[1] != ProtocolDef.MISSION_TYPE_FOLLOW or pm[10] != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mixed payload types: ", pm[1], pm[10]); return false

	# ⑥ 门控收紧（task_41 §3.2）：type=3 缺 `half_side` / type=1（退役 Circle）→
	#    **返回空数组（不降级、不发帧）**（这里的 printerr 是预期输出）
	var p3 := OrionMessages.Encode_Task_Set([{"type": 3, "x": 0.0, "y": 0.0}])
	if not p3.is_empty():
		print("FAIL type=3 without half_side must not encode: ", p3); return false
	var p1 := OrionMessages.Encode_Task_Set([{"type": 1, "x": 0.0, "y": 0.0}])
	if not p1.is_empty():
		print("FAIL type=1 must not encode: ", p1); return false
	# 数字直通到 Encode 之前：门控在 Encode，不在 Mission_Type_From
	if ProtocolDef.Mission_Type_From(3) != 3:
		print("FAIL mission_type_from int 3 passthrough"); return false

	print("PASS follow_task_set"); return true


# ─── task_41 §3.2：Containment(type=3) + 变长 TASK_SET ────────────────────

func _test_containment_task_set() -> bool:
	# ① 常量 + 归一化（"containment"/"contain" → 3；整数原样；"circle"/未知 仍是 0）
	if ProtocolDef.MISSION_TYPE_CONTAINMENT != 3:
		print("FAIL MISSION_TYPE_CONTAINMENT != 3"); return false
	if ProtocolDef.Mission_Type_From("containment") != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL mission_type_from containment"); return false
	if ProtocolDef.Mission_Type_From("CONTAIN") != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL mission_type_from CONTAIN case"); return false
	if ProtocolDef.Mission_Type_From(" containment ") != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL mission_type_from containment trimmed"); return false
	if ProtocolDef.Mission_Type_From(3) != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL mission_type_from int 3 passthrough"); return false
	if ProtocolDef.Mission_Type_From("circle") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from circle must stay Goto"); return false

	# ② 单条 {3, 64, 64, 8} → 14B，金标 0103428000004280000041000000
	#    （与 Rust `test_task_set_containment_golden` / Python `CONTAINMENT_GOLDEN_HEX` 同一枚）
	var p := OrionMessages.Encode_Task_Set([{"type": 3, "x": 64.0, "y": 64.0, "half_side": 8.0}])
	if p.size() != 14 or p[0] != 1:
		print("FAIL containment payload size/count: ", p.size()); return false
	if p[1] != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL containment type byte: ", p[1]); return false
	if p.hex_encode() != "0103428000004280000041000000":
		print("FAIL containment golden bytes: ", p.hex_encode()); return false

	# ③ 混合 [Goto(64,64), Containment(64,64,8)] → 23B；[1]=0、[10]=3、[19..23]=41000000
	var pm := OrionMessages.Encode_Task_Set([
		{"type": 0, "x": 64.0, "y": 64.0},
		{"type": 3, "x": 64.0, "y": 64.0, "half_side": 8.0},
	])
	if pm.size() != 23 or pm[0] != 2:
		print("FAIL mixed containment size/count: ", pm.size()); return false
	if pm[1] != ProtocolDef.MISSION_TYPE_GOTO or pm[10] != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL mixed containment types: ", pm[1], pm[10]); return false
	if pm.slice(19, 23) != PackedByteArray([0x41, 0x00, 0x00, 0x00]):
		print("FAIL mixed containment half_side BE: ", pm.slice(19, 23)); return false
	if pm.hex_encode() != "0200428000004280000003428000004280000041000000":
		print("FAIL mixed containment golden bytes: ", pm.hex_encode()); return false

	# ④ 整帧 roundtrip：half_side 往返；非 3 的 half_side 恒 0.0
	var frame := OrionMessages.Build_Cmd(MessageBuilder.build_task_set([
		{"type": "containment", "x": 64.0, "y": 64.0, "half_side": 8.0},
		{"type": "goto", "x": 1.0, "y": 2.0},
	]))
	if frame.is_empty():
		print("FAIL containment Build_Cmd empty"); return false
	var dec_f := OrionFrame.Decode_Frame(frame)
	if not dec_f.ok:
		print("FAIL containment frame decode: ", dec_f.error); return false
	var ts := OrionMessages.Decode_Task_Set(dec_f.payload)
	if not ts.ok or ts.mission_count != 2:
		print("FAIL containment roundtrip: ", ts); return false
	if ts.missions[0].type != ProtocolDef.MISSION_TYPE_CONTAINMENT:
		print("FAIL containment roundtrip type: ", ts.missions[0]); return false
	if absf(ts.missions[0].half_side - 8.0) > 0.0001:
		print("FAIL containment roundtrip half_side: ", ts.missions[0]); return false
	if absf(ts.missions[1].half_side) > 0.0001:
		print("FAIL goto half_side must be 0.0: ", ts.missions[1]); return false

	# ⑤ 未知 type（9 / 退役 1）→ Encode 返回空数组、Build_Cmd 返回空帧（不降级、不发帧）
	if not OrionMessages.Encode_Task_Set([{"type": 9, "x": 0.0, "y": 0.0}]).is_empty():
		print("FAIL unknown type 9 must not encode"); return false
	if not OrionMessages.Build_Cmd(
			MessageBuilder.build_task_set([{"type": 9, "x": 0.0, "y": 0.0}])).is_empty():
		print("FAIL unknown type 9 must not build frame"); return false
	if not OrionMessages.Encode_Task_Set([{"type": 1, "x": 0.0, "y": 0.0}]).is_empty():
		print("FAIL retired circle type 1 must not encode"); return false

	# ⑥ type=3 的 half_side 门控：缺失 / 0 / 负数 / NaN → 空数组（整帧不发）
	for bad in [null, 0.0, -1.0, NAN]:
		var item2 := {"type": 3, "x": 64.0, "y": 64.0}
		if bad != null:
			item2["half_side"] = bad
		if not OrionMessages.Encode_Task_Set([item2]).is_empty():
			print("FAIL bad half_side accepted: ", bad); return false

	# ⑦ Decode：未知 type / 截断 / 多 1B / half_side=0 → ok == false
	var raw_unknown := PackedByteArray([1, 9, 0, 0, 0, 0, 0, 0, 0, 0])
	if OrionMessages.Decode_Task_Set(raw_unknown).ok:
		print("FAIL decode unknown type accepted"); return false
	var raw_short := PackedByteArray([1, 3, 0x42, 0x80, 0x00, 0x00])
	if OrionMessages.Decode_Task_Set(raw_short).ok:
		print("FAIL decode truncated containment accepted"); return false
	var raw_tail := p.duplicate()
	raw_tail.append(0)
	if OrionMessages.Decode_Task_Set(raw_tail).ok:
		print("FAIL decode trailing byte accepted"); return false
	var raw_zero_half := p.duplicate()
	raw_zero_half[10] = 0x00
	raw_zero_half[11] = 0x00
	raw_zero_half[12] = 0x00
	raw_zero_half[13] = 0x00
	if OrionMessages.Decode_Task_Set(raw_zero_half).ok:
		print("FAIL decode half_side=0 accepted"); return false

	print("PASS containment_task_set"); return true


# ─── task_48 §三：Face(type=4, 9B) ─────────────────────────────

func _test_face_task_set() -> bool:
	# ① 常量
	if ProtocolDef.MISSION_TYPE_FACE != 4:
		print("FAIL MISSION_TYPE_FACE != 4"); return false
	# ② 字符串归一化（未知字符串仍 → 0 = Goto，LLM 防御路径不许破）
	if ProtocolDef.Mission_Type_From("face") != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL mission_type_from face"); return false
	if ProtocolDef.Mission_Type_From("FACE") != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL mission_type_from FACE case"); return false
	if ProtocolDef.Mission_Type_From(" face ") != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL mission_type_from face trimmed"); return false
	if ProtocolDef.Mission_Type_From("guard") != ProtocolDef.MISSION_TYPE_GUARD:
		print("FAIL mission_type_from guard"); return false
	if ProtocolDef.Mission_Type_From("unknown") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from unknown must stay Goto"); return false
	if ProtocolDef.Mission_Type_From("circle") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from circle must stay Goto"); return false
	if ProtocolDef.Mission_Type_From(4) != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL mission_type_from int 4 passthrough"); return false
	# ③ 单条 {4, 64, 64} → 10B，金标 01044280000042800000
	#    （与 Rust `test_task_set_face_golden`(messages.rs:767-779) / Python 逐字同一串）
	var pf := OrionMessages.Encode_Task_Set([{"type": 4, "x": 64.0, "y": 64.0}])
	if pf.size() != 10 or pf[0] != 1:
		print("FAIL face payload size/count: ", pf.size()); return false
	if pf[1] != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL face type byte: ", pf[1]); return false
	if pf.hex_encode() != "01044280000042800000":
		print("FAIL face golden bytes: ", pf.hex_encode()); return false
	# ④ 1.0 / 2.0：防「64.0 的位模式巧合」把 x/y 写反
	var pf2 := OrionMessages.Encode_Task_Set([{"type": 4, "x": 1.0, "y": 2.0}])
	if pf2.size() != 10:
		print("FAIL face(1,2) payload size: ", pf2.size()); return false
	if pf2.hex_encode() != "01043f80000040000000":
		print("FAIL face(1,2) golden bytes: ", pf2.hex_encode()); return false
	# ⑤ [Goto(64,64), Face(64,64)] → 19B；[1]=0、[10]=4（口径 #4 的成对下发，顺序不许反）
	var pfg := OrionMessages.Encode_Task_Set([
		{"type": 0, "x": 64.0, "y": 64.0},
		{"type": 4, "x": 64.0, "y": 64.0},
	])
	if pfg.size() != 19 or pfg[0] != 2:
		print("FAIL goto+face payload size/count: ", pfg.size()); return false
	if pfg[1] != ProtocolDef.MISSION_TYPE_GOTO or pfg[10] != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL goto+face types: ", pfg[1], pfg[10]); return false
	if pfg.hex_encode() != "02004280000042800000044280000042800000":
		print("FAIL goto+face golden bytes: ", pfg.hex_encode()); return false
	# ⑥ 整帧往返（builder → Build_Cmd → Decode_Frame → Decode_Task_Set）
	var ff := OrionMessages.Build_Cmd(MessageBuilder.build_auto_push_goto_face(64.0, 64.0, 64.0, 64.0))
	if ff.is_empty():
		print("FAIL goto+face Build_Cmd empty"); return false
	var df := OrionFrame.Decode_Frame(ff)
	if not df.ok:
		print("FAIL goto+face frame decode: ", df.error); return false
	var tsd := OrionMessages.Decode_Task_Set(df.payload)
	if not tsd.ok or tsd.mission_count != 2:
		print("FAIL goto+face roundtrip: ", tsd); return false
	var fm: Dictionary = tsd.missions[1]
	if fm.type != ProtocolDef.MISSION_TYPE_FACE:
		print("FAIL goto+face roundtrip type: ", fm); return false
	if absf(fm.x - 64.0) > 0.0001 or absf(fm.y - 64.0) > 0.0001:
		print("FAIL goto+face roundtrip x/y: ", fm); return false
	if absf(fm.half_side) > 0.0001:
		print("FAIL face half_side must be 0.0: ", fm); return false
	if absf(fm.fx) > 0.0001 or absf(fm.fy) > 0.0001:
		print("FAIL non-guard fx/fy must be 0.0: ", fm); return false
	# ⑦ 未知 type（9 / 退役 1）仍整帧拒发（口径 #23：编码侧不降级成 Goto）
	if not OrionMessages.Encode_Task_Set([{"type": 9, "x": 0.0, "y": 0.0}]).is_empty():
		print("FAIL unknown type 9 must not encode"); return false
	if not OrionMessages.Encode_Task_Set([{"type": 1, "x": 0.0, "y": 0.0}]).is_empty():
		print("FAIL retired circle type 1 must not encode"); return false
	if not OrionMessages.Build_Cmd(
			MessageBuilder.build_task_set([{"type": 9, "x": 0.0, "y": 0.0}])).is_empty():
		print("FAIL unknown type 9 must not build frame"); return false
	print("PASS face_task_set"); return true


# ─── task_48 §三：Guard(type=5, 17B) ───────────────────────────

func _test_guard_task_set() -> bool:
	# ① 常量
	if ProtocolDef.MISSION_TYPE_GUARD != 5:
		print("FAIL MISSION_TYPE_GUARD != 5"); return false
	# ② 单条 {5, 64, 64, fx=64, fy=128} → 18B，金标 010542800000428000004280000043000000
	#    （与 Rust `test_task_set_guard_golden`(messages.rs:783-792) / Python 逐字同一串）
	var pg := OrionMessages.Encode_Task_Set([
		{"type": 5, "x": 64.0, "y": 64.0, "fx": 64.0, "fy": 128.0},
	])
	if pg.size() != 18 or pg[0] != 1:
		print("FAIL guard payload size/count: ", pg.size()); return false
	if pg[1] != ProtocolDef.MISSION_TYPE_GUARD:
		print("FAIL guard type byte: ", pg[1]); return false
	if pg.slice(10, 14) != PackedByteArray([0x42, 0x80, 0x00, 0x00]):
		print("FAIL guard fx BE: ", pg.slice(10, 14)); return false
	if pg.slice(14, 18) != PackedByteArray([0x43, 0x00, 0x00, 0x00]):
		print("FAIL guard fy BE: ", pg.slice(14, 18)); return false
	if pg.hex_encode() != "010542800000428000004280000043000000":
		print("FAIL guard golden bytes: ", pg.hex_encode()); return false
	# ③ builder 常量直通：build_guard(64, 64, 64, 128)
	var bg := MessageBuilder.build_guard(64.0, 64.0, 64.0, 128.0)
	if not bg.has("missions") or (bg["missions"] as Array).size() != 1:
		print("FAIL build_guard missions: ", bg); return false
	var gm: Dictionary = (bg["missions"] as Array)[0]
	if int(gm.type) != ProtocolDef.MISSION_TYPE_GUARD:
		print("FAIL build_guard type: ", gm); return false
	if absf(float(gm.fx) - 64.0) > 0.0001 or absf(float(gm.fy) - 128.0) > 0.0001:
		print("FAIL build_guard fx/fy: ", gm); return false
	# ④ `build_task_set` 必须**透传** fx/fy（漏了就丢：ws `guard` / `task_set` 通道会把注视点编成 0）
	var bts := MessageBuilder.build_task_set(
			[{"type": "guard", "x": 1.0, "y": 2.0, "fx": 3.0, "fy": 4.0}])
	var tm: Dictionary = (bts["missions"] as Array)[0]
	if not tm.has("fx") or not tm.has("fy"):
		print("FAIL build_task_set dropped fx/fy: ", tm); return false
	var pgt := OrionMessages.Encode_Task_Set(bts["missions"])
	var gd := OrionMessages.Decode_Task_Set(pgt)
	if not gd.ok or gd.mission_count != 1:
		print("FAIL guard build_task_set roundtrip: ", gd); return false
	var g0: Dictionary = gd.missions[0]
	if absf(g0.x - 1.0) > 0.0001 or absf(g0.y - 2.0) > 0.0001:
		print("FAIL guard roundtrip x/y: ", g0); return false
	if absf(g0.fx - 3.0) > 0.0001 or absf(g0.fy - 4.0) > 0.0001:
		print("FAIL guard roundtrip fx/fy: ", g0); return false
	# ⑤ 非 guard 的 fx/fy 恒 0（Goto 往返）
	var gd2 := OrionMessages.Decode_Task_Set(
			OrionMessages.Encode_Task_Set([{"type": 0, "x": 1.0, "y": 2.0}]))
	if not gd2.ok:
		print("FAIL goto roundtrip: ", gd2); return false
	if absf(gd2.missions[0].fx) > 0.0001 or absf(gd2.missions[0].fy) > 0.0001:
		print("FAIL goto fx/fy must be 0.0: ", gd2.missions[0]); return false
	# ⑥ 长度不符整帧拒（少 1B / 多 1B）—— 口径 #22 的旧端语义
	var short_g := pg.slice(0, 17)
	if OrionMessages.Decode_Task_Set(short_g).ok:
		print("FAIL guard short frame accepted"); return false
	var tail_g := pg.duplicate()
	tail_g.append(0)
	if OrionMessages.Decode_Task_Set(tail_g).ok:
		print("FAIL guard trailing byte accepted"); return false
	# ⑦ type=5 缺 fx/fy 时编码器**不报错也不拒**（与 Rust `decode_task_set` 「不做有限性校验」同口径）
	#    —— 把「B 端缺省 0.0」这个契约固定下来，避免以后误加校验
	var pz := OrionMessages.Encode_Task_Set([{"type": 5, "x": 1.0, "y": 2.0}])
	if pz.size() != 18:
		print("FAIL guard without fx/fy size: ", pz.size()); return false
	if pz.slice(10, 18) != PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]):
		print("FAIL guard without fx/fy must be zeros: ", pz.slice(10, 18)); return false
	print("PASS guard_task_set"); return true


# ─── Task 21：log-odds 语义边界用例 ────────────────────────────

func _test_log_odds_signed() -> bool:
	# u8 ↔ i8 位模式转换（ChunkData2D 辅助）
	if ChunkData2D.to_i8(0xF8) != -8:
		print("FAIL to_i8(0xF8)"); return false
	if ChunkData2D.to_i8(0xFF) != -1:
		print("FAIL to_i8(0xFF)"); return false
	if ChunkData2D.to_i8(0x80) != -128:
		print("FAIL to_i8(0x80)"); return false
	if ChunkData2D.to_i8(0x08) != 8:
		print("FAIL to_i8(0x08)"); return false
	if ChunkData2D.to_u8(-8) != 248 or ChunkData2D.to_u8(-1) != 255:
		print("FAIL to_u8 negatives"); return false
	if ChunkData2D.to_u8(8) != 8:
		print("FAIL to_u8(8)"); return false
	if ChunkData2D.to_i8(ChunkData2D.to_u8(-15)) != -15:
		print("FAIL signed roundtrip -15"); return false
	print("PASS log_odds_signed"); return true


func _test_clamp() -> bool:
	# 接收方语义：new = clamp(old + Δ, −8, +8)，先加后 clamp（Δ 可超 ±8）
	if clampi(6 + 2, -8, 8) != 8:
		print("FAIL clamp 6+2"); return false
	if clampi(-8 + (-3), -8, 8) != -8:
		print("FAIL clamp -8-3"); return false
	if clampi(8 + 1, -8, 8) != 8:
		print("FAIL clamp 8+1 saturated"); return false
	if clampi(-8 + 1, -8, 8) != -7:
		print("FAIL clamp -8+1"); return false
	if clampi(-8 + 15, -8, 8) != 7:
		print("FAIL clamp -8+15 (aggregated Δ=+15)"); return false
	print("PASS clamp"); return true


func _test_threshold() -> bool:
	# 阈值派生严格边界：>+6 Occupied / <−6 Free / 恰好 ±6 与 0 为 Unknown
	if ChunkData2D.to_state(6) != ProtocolDef.CELL_UNKNOWN:
		print("FAIL to_state(6) should be Unknown"); return false
	if ChunkData2D.to_state(7) != ProtocolDef.CELL_OCCUPIED:
		print("FAIL to_state(7) should be Occupied"); return false
	if ChunkData2D.to_state(-6) != ProtocolDef.CELL_UNKNOWN:
		print("FAIL to_state(-6) should be Unknown"); return false
	if ChunkData2D.to_state(-7) != ProtocolDef.CELL_FREE:
		print("FAIL to_state(-7) should be Free"); return false
	if ChunkData2D.to_state(0) != ProtocolDef.CELL_UNKNOWN:
		print("FAIL to_state(0) should be Unknown"); return false
	if ChunkData2D.to_state(8) != ProtocolDef.CELL_OCCUPIED:
		print("FAIL to_state(8)"); return false
	if ChunkData2D.to_state(-8) != ProtocolDef.CELL_FREE:
		print("FAIL to_state(-8)"); return false
	print("PASS threshold"); return true


# ─── Task 21 阶段 2：终端返还合并全量（msgid=2 下行）─────────────

func _test_build_cmd_map_full() -> bool:
	# build_map_full → Build_Cmd(msgid=2) → roundtrip
	var cells := PackedByteArray()
	cells.resize(65536)
	cells[0] = 8
	cells[1] = ChunkData2D.to_u8(-8)
	var frame := OrionMessages.Build_Cmd(MessageBuilder.build_map_full(cells))
	if frame.is_empty():
		print("FAIL build_map_full frame empty"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	if not dec.ok or dec.msgid != 2 or not dec.sysid.is_empty() or dec.compid != 200:
		print("FAIL build_map_full frame: ", dec); return false
	var full := OrionMessages.Decode_Map_Full(dec.payload)
	if not full.ok:
		print("FAIL build_map_full decode: ", full.error); return false
	if full.origin_gx != 0 or full.origin_gy != 0 or full.width != 256 or full.height != 256:
		print("FAIL build_map_full meta: ", full); return false
	if absf(full.resolution - 0.5) > 1e-6 or full.data.size() != 65536:
		print("FAIL build_map_full res/size"); return false
	if full.data[0] != 8 or ChunkData2D.to_i8(full.data[1]) != -8:
		print("FAIL build_map_full data"); return false
	print("PASS build_cmd_map_full"); return true


func _test_return_frame_size() -> bool:
	# 返还整帧大小 = 帧头 10 + 空 sysid 0 + payload 65556 + checksum 2 = 65568 > 默认 buffer 65535
	var cells := PackedByteArray()
	cells.resize(65536)
	var frame := OrionMessages.Build_Cmd(MessageBuilder.build_map_full(cells))
	if frame.size() != 65568:
		print("FAIL return frame size: ", frame.size(), " (expect 65568, > 65535 → buffer 须调大)"); return false
	print("PASS return_frame_size (65568B > default 65535 → buffer 1<<22 已验证)"); return true


func _test_map_accumulator() -> bool:
	# add_full：整表累加 + clamp
	var a := PackedByteArray()
	a.resize(4)
	a[0] = 8; a[1] = ChunkData2D.to_u8(-8); a[2] = 3; a[3] = 0
	var b := PackedByteArray()
	b.resize(4)
	b[0] = 8; b[1] = 0; b[2] = 0; b[3] = ChunkData2D.to_u8(-6)
	var s := MapAccumulator.add_full(a, b)
	# clamp(8+8)=8；clamp(-8+0)=-8；3+0=3；clamp(0-6)=-6
	if ChunkData2D.to_i8(s[0]) != 8 or ChunkData2D.to_i8(s[1]) != -8 \
			or ChunkData2D.to_i8(s[2]) != 3 or ChunkData2D.to_i8(s[3]) != -6:
		print("FAIL add_full: ", [ChunkData2D.to_i8(s[0]), ChunkData2D.to_i8(s[1]), ChunkData2D.to_i8(s[2]), ChunkData2D.to_i8(s[3])]); return false
	# apply_delta_bytes：先加后 clamp
	var voxels := [
		{"gx": 0, "gy": 0, "delta": 3},
		{"gx": 0, "gy": 0, "delta": 3},
		{"gx": 1, "gy": 0, "delta": 15},   # 聚合 Δ 超 ±8：-8+15=7
		{"gx": 999, "gy": 999, "delta": 8}, # 越界忽略
	]
	var t := PackedByteArray()
	t.resize(65536)
	t[1] = ChunkData2D.to_u8(-8)
	var r := MapAccumulator.apply_delta_bytes(t, voxels)
	if ChunkData2D.to_i8(r[0]) != 6:  # 0+3+3=6（饱和前）
		print("FAIL apply_delta 0,0: ", ChunkData2D.to_i8(r[0])); return false
	if ChunkData2D.to_i8(r[1]) != 7:  # -8+15=7
		print("FAIL apply_delta 1,0: ", ChunkData2D.to_i8(r[1])); return false
	print("PASS map_accumulator"); return true


# ─── 大端字节序断言（与 Rust 端字节逐一比对）──────────────────────

func _test_endianness() -> bool:
	# 1) 帧 len 大端（空身份）：payload 5 → [00 00 00 05]；msgid 3 → [00 03]@8-9
	var f := OrionFrame.Encode_Frame(3, PackedByteArray(), 1, PackedByteArray([1, 2, 3, 4, 5]))
	var len_bytes := f.slice(1, 5)
	if len_bytes != PackedByteArray([0x00, 0x00, 0x00, 0x05]):
		print("FAIL frame len BE bytes: ", len_bytes); return false
	if f[6] != 0:
		print("FAIL empty sysid_len"); return false
	if f.slice(8, 10) != PackedByteArray([0x00, 0x03]):
		print("FAIL frame msgid BE bytes"); return false

	# 1b) 变长 sysid>0：sysid=[01 02 03] → compid@10、msgid@11-12、payload@13
	var f2 := OrionFrame.Encode_Frame(5, PackedByteArray([0x01, 0x02, 0x03]), 7, PackedByteArray([0xAA]))
	if f2[6] != 3:
		print("FAIL sysid_len=3"); return false
	if f2[7] != 0x01 or f2[8] != 0x02 or f2[9] != 0x03:
		print("FAIL sysid bytes"); return false
	if f2[10] != 7:
		print("FAIL compid@10"); return false
	if f2.slice(11, 13) != PackedByteArray([0x00, 0x05]):
		print("FAIL msgid@11-12"); return false
	if f2[13] != 0xAA:
		print("FAIL payload@13"); return false
	var dec2 := OrionFrame.Decode_Frame(f2)
	if not dec2.ok or dec2.sysid != PackedByteArray([0x01, 0x02, 0x03]) or dec2.compid != 7 or dec2.msgid != 5:
		print("FAIL varlen sysid roundtrip: ", dec2); return false

	# 2) 模拟真实 Rust v2 帧（map_full 65556，带 34B peer_id）→ Decode_Frame 必须正确读出
	var peer_id := PackedByteArray()
	peer_id.resize(34)
	for i in range(34):
		peer_id[i] = 0x10 + i
	var rust_frame := OrionFrame.Encode_Frame(2, peer_id, 1, PackedByteArray())
	# 手动补 65556 字节 payload 验证大帧
	var big := PackedByteArray()
	big.resize(65556)
	var rust_big := OrionFrame.Encode_Frame(2, peer_id, 1, big)
	var dec := OrionFrame.Decode_Frame(rust_big)
	if not dec.ok:
		print("FAIL rust v2 BE frame decode: ", dec.error); return false
	if dec.msgid != 2 or dec.payload.size() != 65556 or dec.sysid.size() != 34:
		print("FAIL rust v2 BE frame fields"); return false

	# 3) pose float 大端：x=1.5 → 0x3FC00000 → [3F C0 00 00]
	var pose := OrionMessages.Encode_Pose(0, 1.5, 0.0, 0.0, 0.0, 0.0)
	if pose.slice(4, 8) != PackedByteArray([0x3F, 0xC0, 0x00, 0x00]):
		print("FAIL pose float BE: ", pose.slice(4, 8)); return false
	# 3b) pose z 大端：z=3.5 → 0x40600000 → [40 60 00 00] @offset 12
	var pose_z := OrionMessages.Encode_Pose(0, 0.0, 0.0, 0.0, 0.0, 0.0, false, 0, 0, 3.5)
	if pose_z.slice(12, 16) != PackedByteArray([0x40, 0x60, 0x00, 0x00]):
		print("FAIL pose z float BE: ", pose_z.slice(12, 16)); return false
	# 3c) pose rtk_fixed 字节：true → 0x01 @offset 37
	var pose_rtk := OrionMessages.Encode_Pose(0, 0.0, 0.0, 0.0, 0.0, 0.0, false, 0, 0, 0.0, true)
	if pose_rtk[37] != 0x01:
		print("FAIL pose rtk_fixed byte: ", pose_rtk[37]); return false

	# 4) map_full resolution 0.5 → 0x3F000000；origin_gx=-256 → [FF FF FF 00]
	var mf := OrionMessages.Encode_Map_Full(0, -256, 256, 256, 256, 0.5, PackedByteArray())
	if mf.slice(4, 8) != PackedByteArray([0xFF, 0xFF, 0xFF, 0x00]):
		print("FAIL map_full s32 BE: ", mf.slice(4, 8)); return false
	if mf.slice(16, 20) != PackedByteArray([0x3F, 0x00, 0x00, 0x00]):
		print("FAIL map_full f32 BE: ", mf.slice(16, 20)); return false

	# 5) manual 事件 param i16 大端：-50 → [FF CE]（task_44：3 B 只剩事件帧）
	var mc := OrionMessages.Encode_Manual_Event(ProtocolDef.ACTION_BEEP, -50)
	if mc.slice(1, 3) != PackedByteArray([0xFF, 0xCE]):
		print("FAIL manual param i16 BE: ", mc.slice(1, 3)); return false
	# 5b) manual 运动 f32 大端：v=0.45 → 0x3EE66666 → [3E E6 66 66]（§1.2 #11 定值）
	var mm := OrionMessages.Encode_Manual_Motion(ProtocolDef.MANUAL_V_MAX, 0.0)
	if mm.slice(0, 4) != PackedByteArray([0x3E, 0xE6, 0x66, 0x66]):
		print("FAIL manual v f32 BE: ", mm.slice(0, 4)); return false

	# 6) task_set x=12.5 → 0x41480000 → [41 48 00 00]（偏移 2..6：跳过 [m_count][type]，task_36 无成员段）
	var ts := OrionMessages.Encode_Task_Set([{"type": 0, "x": 12.5, "y": 0.0}])
	if ts.slice(2, 6) != PackedByteArray([0x41, 0x48, 0x00, 0x00]):
		print("FAIL task_set f32 BE: ", ts.slice(2, 6)); return false

	# 7) map_delta delta i8：-8 → 0xF8 位模式（Task 21）
	var md := OrionMessages.Encode_Map_Delta(0, [{"gx": 0, "gy": 0, "delta": -8}])
	if md[6 + 8] != 0xF8:
		print("FAIL map_delta delta i8 byte: ", md[6 + 8]); return false
	var dec_md := OrionMessages.Decode_Map_Delta(md)
	if dec_md.entries[0].delta != -8:
		print("FAIL map_delta decode -8: ", dec_md.entries[0]); return false

	print("PASS endianness (BE bytes match Rust)"); return true


# ─── task_36 §12.7.5：地面站逐车算点（占位实现）───────────────

func _test_target_alloc() -> bool:
	# 位姿门控：x/y 都为 0 = 尚未收到位姿 → 剔除；未注册的车也算无位姿
	var ids: Array[String] = ["a", "b", "c"]
	var table := {
		"a": {"name": "车A", "x": 0.0, "y": 0.0},
		"b": {"name": "车B", "x": 3.0, "y": 4.0},
		"c": {"name": "车C", "x": 0.0, "y": -2.0},
	}
	var gate := TargetAlloc.filter_placeable(ids, table)
	if gate.ok.size() != 2 or gate.rejected.size() != 1:
		print("FAIL target_alloc filter sizes: ", gate); return false
	if gate.rejected[0] != "a":
		print("FAIL target_alloc rejected: ", gate.rejected); return false
	if gate.ok[0] != "b" or gate.ok[1] != "c":
		print("FAIL target_alloc ok order: ", gate.ok); return false
	var ghost_ids: Array[String] = ["ghost"]
	var gate2 := TargetAlloc.filter_placeable(ghost_ids, table)
	if not gate2.ok.is_empty() or gate2.rejected.size() != 1:
		print("FAIL target_alloc unknown id: ", gate2); return false

	# 占位算法：全部返回同一锚点；shape 只是占位参数，不影响结果
	var anchor := Vector2(5.0, -1.5)
	var pts := TargetAlloc.compute_targets(gate.ok, anchor, "goto")
	if pts.size() != 2 or pts["b"] != anchor or pts["c"] != anchor:
		print("FAIL compute_targets placeholder: ", pts); return false
	var pts_circle := TargetAlloc.compute_targets(gate.ok, anchor, "circle")
	if pts_circle["b"] != anchor or pts_circle["c"] != anchor:
		print("FAIL compute_targets shape ignored: ", pts_circle); return false
	print("PASS target_alloc"); return true


# ─── task_41 §5.3：ASSIST_REQUEST（msgid 7，上行 8B）─────────────────────

func _test_assist_request() -> bool:
	if ProtocolDef.MSGID_ASSIST_REQUEST != 7:
		print("FAIL MSGID_ASSIST_REQUEST != 7"); return false
	# ① 金标：x=1.0 → 3F800000、y=2.0 → 40000000（与 Rust `test_assist_request_golden` 同一串）
	var p := PackedByteArray()
	p.resize(8)
	OrionFrame.Write_F32_BE(p, 0, 1.0)
	OrionFrame.Write_F32_BE(p, 4, 2.0)
	if p.hex_encode() != "3f80000040000000":
		print("FAIL assist golden bytes: ", p.hex_encode()); return false
	var d := OrionMessages.Decode_Assist_Request(p)
	if not d.ok or absf(d.x - 1.0) > 1e-6 or absf(d.y - 2.0) > 1e-6:
		print("FAIL assist decode: ", d); return false
	# ② 长度严格：7B / 9B / 空 → 拒
	if OrionMessages.Decode_Assist_Request(p.slice(0, 7)).ok:
		print("FAIL assist 7B accepted"); return false
	var nine := p.duplicate(); nine.append(0)
	if OrionMessages.Decode_Assist_Request(nine).ok:
		print("FAIL assist 9B accepted"); return false
	if OrionMessages.Decode_Assist_Request(PackedByteArray()).ok:
		print("FAIL assist empty accepted"); return false
	# ③ 非有限值拒（与 Rust `decode_assist_request` 同口径）
	var nan_p := PackedByteArray(); nan_p.resize(8)
	OrionFrame.Write_F32_BE(nan_p, 0, NAN)
	OrionFrame.Write_F32_BE(nan_p, 4, 0.0)
	if OrionMessages.Decode_Assist_Request(nan_p).ok:
		print("FAIL assist NaN accepted"); return false
	# ④ parser 分发：msgid 7 + 1B sysid（模拟 UAV 身份）
	var frame := OrionFrame.Encode_Frame(7, PackedByteArray([7]), 1, p)
	var r := MessageParser.parse_orion_frame(frame)
	if not r.ok or r.msgid != 7:
		print("FAIL parser assist: ", r); return false
	if r.sysid != PackedByteArray([7]) or absf(r.data.x - 1.0) > 1e-6:
		print("FAIL parser assist fields: ", r); return false
	print("PASS assist_request"); return true
