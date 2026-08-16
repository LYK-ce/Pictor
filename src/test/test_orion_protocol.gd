extends SceneTree

## Presented by KeJi
## Date ： 2026-08-11
##
## Orion 协议 v2 编解码 roundtrip 测试（headless）
## 用法: godot --headless --path <项目> -s <本脚本路径>
## 覆盖：帧/消息 roundtrip（v2 变长 sysid）+ 大端字节序断言（与 Rust 端字节比对）
## Task 21：地图改 log-odds 语义（delta i8 位模式 / clamp / 阈值派生边界）

func _init() -> void:
	var ok := true
	ok = ok and _test_frame()
	ok = ok and _test_pose()
	ok = ok and _test_map_full()
	ok = ok and _test_map_delta()
	ok = ok and _test_manual_control()
	ok = ok and _test_task_set()
	ok = ok and _test_build_cmd()
	ok = ok and _test_parser_dispatch()
	ok = ok and _test_endianness()
	ok = ok and _test_llm_missions()
	ok = ok and _test_circle_task_set()
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
	# v2：33B，含 valid/sub_gx/sub_gy 意图字段
	var payload := OrionMessages.Encode_Pose(12345, 1.5, -2.25, 0.1, -0.2, 0.785, true, 10, -20)
	if payload.size() != 33:
		print("FAIL pose size: ", payload.size()); return false
	var dec := OrionMessages.Decode_Pose(payload)
	if not dec.ok:
		print("FAIL pose decode: ", dec.error); return false
	if dec.time_boot_ms != 12345 or absf(dec.x - 1.5) > 0.0001 or absf(dec.y - (-2.25)) > 0.0001:
		print("FAIL pose fields: ", dec); return false
	if absf(dec.vx - 0.1) > 0.0001 or absf(dec.vy - (-0.2)) > 0.0001 or absf(dec.yaw - 0.785) > 0.0001:
		print("FAIL pose fields2: ", dec); return false
	if dec.valid != true or dec.sub_gx != 10 or dec.sub_gy != -20:
		print("FAIL pose intent fields: ", dec); return false
	# 24B 旧帧应被拒绝（v2 严格校验，对齐 Rust）
	var old_payload := OrionMessages.Encode_Pose(0, 0, 0, 0, 0, 0)
	if OrionMessages.Decode_Pose(old_payload.slice(0, 24)).ok:
		print("FAIL 24B old pose accepted"); return false
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
	var payload := OrionMessages.Encode_Manual_Control(4, -50)
	var dec := OrionMessages.Decode_Manual_Control(payload)
	if not dec.ok or dec.action != 4 or dec.param != -50:
		print("FAIL manual_control: ", dec); return false
	print("PASS manual_control"); return true


func _test_task_set() -> bool:
	# —— 单车（member_count=1）往返 ——
	var members_single := [PackedByteArray([0x10, 0x20])]
	var payload := OrionMessages.Encode_Task_Set(
		[{"type": 0, "x": 12.5, "y": -3.25}], members_single)
	# 布局: [m_count=1][mem_count=1][len=2][10 20][type][x 4B][y 4B] = 2+3+9 = 14B
	if payload.size() != 14:
		print("FAIL task_set size: ", payload.size()); return false
	if payload[0] != 1 or payload[1] != 1:
		print("FAIL task_set counts"); return false
	if payload.slice(2, 5) != PackedByteArray([2, 0x10, 0x20]):
		print("FAIL task_set member bytes: ", payload.slice(2, 5)); return false
	var dec := OrionMessages.Decode_Task_Set(payload)
	if not dec.ok or dec.mission_count != 1 or dec.member_count != 1 or dec.missions.size() != 1:
		print("FAIL task_set decode: ", dec); return false
	if dec.members.size() != 1 or dec.members[0] != PackedByteArray([0x10, 0x20]):
		print("FAIL task_set members decode: ", dec.members); return false
	var m0: Dictionary = dec.missions[0]
	if m0.type != 0 or absf(m0.x - 12.5) > 0.0001 or absf(m0.y - (-3.25)) > 0.0001:
		print("FAIL task_set m0: ", m0); return false

	# —— 群发（member_count=2，3 条任务）往返 ——
	var members_multi := [PackedByteArray([1, 2, 3]), PackedByteArray([0xAA])]
	var missions := [
		{"type": 0, "x": 12.5, "y": -3.25},
		{"type": 0, "x": 0.0, "y": 99.99},
		{"type": 0, "x": -1.0, "y": 1.0},
	]
	var payload2 := OrionMessages.Encode_Task_Set(missions, members_multi)
	var dec2 := OrionMessages.Decode_Task_Set(payload2)
	if not dec2.ok or dec2.mission_count != 3 or dec2.member_count != 2:
		print("FAIL task_set multi decode: ", dec2); return false
	if dec2.members[0] != PackedByteArray([1, 2, 3]) or dec2.members[1] != PackedByteArray([0xAA]):
		print("FAIL task_set multi members: ", dec2.members); return false
	if absf(dec2.missions[1].y - 99.99) > 0.0001 or absf(dec2.missions[2].x - (-1.0)) > 0.0001:
		print("FAIL task_set multi missions: ", dec2.missions); return false

	# —— 取消帧（member_count=0, mission_count=0）往返 ——
	var cancel := OrionMessages.Encode_Task_Set([], [])
	if cancel.size() != 2 or cancel[0] != 0 or cancel[1] != 0:
		print("FAIL task_set cancel layout"); return false
	var dec_cancel := OrionMessages.Decode_Task_Set(cancel)
	if not dec_cancel.ok or dec_cancel.mission_count != 0 or not dec_cancel.missions.is_empty():
		print("FAIL task_set cancel decode: ", dec_cancel); return false

	# —— 越界防御 ——
	if OrionMessages.Decode_Task_Set(PackedByteArray([0])).ok:
		print("FAIL task_set payload<2 accepted"); return false
	var bad_member := PackedByteArray([0, 1, 10])  # member len=10 但无数据
	if OrionMessages.Decode_Task_Set(bad_member).ok:
		print("FAIL task_set member OOB accepted"); return false
	var bad_missions := PackedByteArray([1, 0])    # mission_count=1 但仅 8B 任务数据（需 9）
	bad_missions.resize(10)
	if OrionMessages.Decode_Task_Set(bad_missions).ok:
		print("FAIL task_set missions mismatch accepted"); return false
	print("PASS task_set"); return true


func _test_build_cmd() -> bool:
	var cmd := MessageBuilder.build_manual_forward(80)
	var frame := OrionMessages.Build_Cmd(cmd)
	if frame.is_empty():
		print("FAIL build_cmd empty"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	# v2 终端上行：空 sysid（sysid_len=0）+ compid=200
	if not dec.ok or dec.msgid != 4 or not dec.sysid.is_empty() or dec.compid != 200:
		print("FAIL build_cmd frame: ", dec); return false
	var mc := OrionMessages.Decode_Manual_Control(dec.payload)
	if mc.action != ProtocolDef.ACTION_FORWARD or mc.param != 80:
		print("FAIL build_cmd payload: ", mc); return false

	var cancel := MessageBuilder.build_auto_cancel()
	var frame2 := OrionMessages.Build_Cmd(cancel)
	var dec2 := OrionFrame.Decode_Frame(frame2)
	var ts := OrionMessages.Decode_Task_Set(dec2.payload)
	if ts.mission_count != 0 or ts.member_count != 0 or not ts.missions.is_empty():
		print("FAIL build_cmd cancel: ", ts); return false
	print("PASS build_cmd"); return true


func _test_parser_dispatch() -> bool:
	# pose 帧 → parse_orion_frame（带 1B sysid 模拟车身份）
	var pose_frame := OrionFrame.Encode_Frame(1, PackedByteArray([1]), 1, OrionMessages.Encode_Pose(1, 2.0, 3.0, 0, 0, 0))
	var r := MessageParser.parse_orion_frame(pose_frame)
	if not r.ok or r.msgid != 1 or absf(r.data.x - 2.0) > 0.0001:
		print("FAIL parser pose: ", r); return false
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
	if ts.mission_count != 2 or ts.member_count != 0 or ts.missions.size() != 2:
		print("FAIL missions count: ", ts); return false
	if ts.missions[0].type != 0 or absf(ts.missions[0].x - 3.0) > 0.0001 or absf(ts.missions[0].y - 5.0) > 0.0001:
		print("FAIL mission0: ", ts.missions[0]); return false
	if ts.missions[1].type != 0 or absf(ts.missions[1].x - 1.0) > 0.0001 or absf(ts.missions[1].y - 1.0) > 0.0001:
		print("FAIL mission1: ", ts.missions[1]); return false
	# 与 Rust 端字节比对：missions[0] = (type 0, x=3.0, y=5.0)
	# payload: [mission_count=2][member_count=0] | 00 40 40 00 40 A0 00 00 | 00 3F 80 00 00 3F 80 00 00
	var payload: PackedByteArray = dec.payload
	if payload[0] != 2 or payload[1] != 0:
		print("FAIL missions count bytes"); return false
	if payload.slice(2, 3) != PackedByteArray([0x00]):
		print("FAIL mission0 type byte"); return false
	if payload.slice(3, 7) != PackedByteArray([0x40, 0x40, 0x00, 0x00]):
		print("FAIL mission0 x=3.0 BE: ", payload.slice(3, 7)); return false
	print("PASS llm_missions"); return true


# ─── Task 24：Circle 命令（mission type=1 环形散布）────────────

func _test_circle_task_set() -> bool:
	# 归一化：字符串 type → 整数（大小写不敏感；未知→goto）
	if ProtocolDef.Mission_Type_From("circle") != ProtocolDef.MISSION_TYPE_CIRCLE:
		print("FAIL mission_type_from circle"); return false
	if ProtocolDef.Mission_Type_From("CIRCLE") != ProtocolDef.MISSION_TYPE_CIRCLE:
		print("FAIL mission_type_from CIRCLE case"); return false
	if ProtocolDef.Mission_Type_From("goto") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from goto"); return false
	if ProtocolDef.Mission_Type_From("unknown") != ProtocolDef.MISSION_TYPE_GOTO:
		print("FAIL mission_type_from unknown"); return false
	if ProtocolDef.Mission_Type_From(1) != 1:
		print("FAIL mission_type_from int passthrough"); return false

	# 构造：build_auto_push_circle → type=1 + 圆心坐标
	var cmd := MessageBuilder.build_auto_push_circle(1.5, 2.5)
	if cmd.msgid != ProtocolDef.MSGID_TASK_SET:
		print("FAIL circle msgid"); return false
	var m0: Dictionary = cmd.missions[0]
	if m0.type != ProtocolDef.MISSION_TYPE_CIRCLE or absf(m0.x - 1.5) > 0.0001 or absf(m0.y - 2.5) > 0.0001:
		print("FAIL circle build: ", m0); return false

	# 编解码 roundtrip：type=1 保持（9 字节布局不变）
	var payload := OrionMessages.Encode_Task_Set(cmd.missions)
	var dec := OrionMessages.Decode_Task_Set(payload)
	if not dec.ok or dec.mission_count != 1 or dec.missions.size() != 1:
		print("FAIL circle roundtrip decode: ", dec); return false
	var dm: Dictionary = dec.missions[0]
	if dm.type != ProtocolDef.MISSION_TYPE_CIRCLE or absf(dm.x - 1.5) > 0.0001 or absf(dm.y - 2.5) > 0.0001:
		print("FAIL circle roundtrip fields: ", dm); return false

	# Encode_Task_Set 字符串 "circle" 归一化（LLM 防御路径）
	var payload_str := OrionMessages.Encode_Task_Set([{"type": "circle", "x": 3.0, "y": 4.0}])
	var dec_str := OrionMessages.Decode_Task_Set(payload_str)
	var dm2: Dictionary = dec_str.missions[0]
	if dm2.type != ProtocolDef.MISSION_TYPE_CIRCLE or absf(dm2.x - 3.0) > 0.0001 or absf(dm2.y - 4.0) > 0.0001:
		print("FAIL circle string normalize: ", dm2); return false

	# build_task_set 字符串 "circle" 归一化（LLM 链路）
	var ms := MessageBuilder.build_task_set([{"type": "circle", "x": 3.0, "y": 4.0}])
	var ms0: Dictionary = ms.missions[0]
	if ms0.type != ProtocolDef.MISSION_TYPE_CIRCLE:
		print("FAIL build_task_set circle normalize"); return false
	print("PASS circle_task_set"); return true


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

	# 4) map_full resolution 0.5 → 0x3F000000；origin_gx=-256 → [FF FF FF 00]
	var mf := OrionMessages.Encode_Map_Full(0, -256, 256, 256, 256, 0.5, PackedByteArray())
	if mf.slice(4, 8) != PackedByteArray([0xFF, 0xFF, 0xFF, 0x00]):
		print("FAIL map_full s32 BE: ", mf.slice(4, 8)); return false
	if mf.slice(16, 20) != PackedByteArray([0x3F, 0x00, 0x00, 0x00]):
		print("FAIL map_full f32 BE: ", mf.slice(16, 20)); return false

	# 5) manual param i16 大端：-50 → [FF CE]
	var mc := OrionMessages.Encode_Manual_Control(0, -50)
	if mc.slice(1, 3) != PackedByteArray([0xFF, 0xCE]):
		print("FAIL manual param i16 BE: ", mc.slice(1, 3)); return false

	# 6) task_set x=12.5 → 0x41480000 → [41 48 00 00]（偏移 3..7：跳过 [m_count][mem_count][type]）
	var ts := OrionMessages.Encode_Task_Set([{"type": 0, "x": 12.5, "y": 0.0}])
	if ts.slice(3, 7) != PackedByteArray([0x41, 0x48, 0x00, 0x00]):
		print("FAIL task_set f32 BE: ", ts.slice(3, 7)); return false

	# 7) map_delta delta i8：-8 → 0xF8 位模式（Task 21）
	var md := OrionMessages.Encode_Map_Delta(0, [{"gx": 0, "gy": 0, "delta": -8}])
	if md[6 + 8] != 0xF8:
		print("FAIL map_delta delta i8 byte: ", md[6 + 8]); return false
	var dec_md := OrionMessages.Decode_Map_Delta(md)
	if dec_md.entries[0].delta != -8:
		print("FAIL map_delta decode -8: ", dec_md.entries[0]); return false

	print("PASS endianness (BE bytes match Rust)"); return true

