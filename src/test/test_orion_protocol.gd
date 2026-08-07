extends SceneTree

## Orion 协议编解码 roundtrip 测试（headless）
## 用法: godot --headless --path <项目> -s <本脚本路径>
## 覆盖：帧/消息 roundtrip + 大端字节序断言（与 Rust 端字节比对）

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
	ok = ok and _test_llm_string_type()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


func _test_frame() -> bool:
	var payload := PackedByteArray([1, 2, 3, 4, 5])
	var frame := OrionFrame.Encode_Frame(3, 200, 1, payload)
	if frame[0] != 0x4F:
		print("FAIL magic"); return false
	# len 字段大端：5 → [00 00 00 05]
	if frame[1] != 0x00 or frame[2] != 0x00 or frame[3] != 0x00 or frame[4] != 0x05:
		print("FAIL len BE: ", frame.slice(1, 5)); return false
	if frame[6] != 200 or frame[7] != 1:
		print("FAIL sysid/compid"); return false
	# msgid 大端：3 → [00 03]
	if frame[8] != 0x00 or frame[9] != 0x03:
		print("FAIL msgid BE"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	if not dec.ok:
		print("FAIL decode: ", dec.error); return false
	if dec.msgid != 3 or dec.sysid != 200 or dec.compid != 1 or dec.payload != payload:
		print("FAIL fields"); return false
	# 错误路径
	if OrionFrame.Decode_Frame(PackedByteArray([0x50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])).ok:
		print("FAIL bad magic accepted"); return false
	if OrionFrame.Decode_Frame(frame.slice(0, 10)).ok:
		print("FAIL truncated accepted"); return false
	print("PASS frame"); return true


func _test_pose() -> bool:
	var payload := OrionMessages.Encode_Pose(12345, 1.5, -2.25, 0.1, -0.2, 0.785)
	var dec := OrionMessages.Decode_Pose(payload)
	if not dec.ok:
		print("FAIL pose decode: ", dec.error); return false
	if dec.time_boot_ms != 12345 or absf(dec.x - 1.5) > 0.0001 or absf(dec.y - (-2.25)) > 0.0001:
		print("FAIL pose fields: ", dec); return false
	if absf(dec.vx - 0.1) > 0.0001 or absf(dec.vy - (-0.2)) > 0.0001 or absf(dec.yaw - 0.785) > 0.0001:
		print("FAIL pose fields2: ", dec); return false
	print("PASS pose"); return true


func _test_map_full() -> bool:
	var data := PackedByteArray()
	data.resize(256 * 256)
	for i in range(data.size()):
		data[i] = (i % 3) * 100  # 0 / 100 / 200
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
	if dec.data[3] != 0 or dec.data[4] != 100 or dec.data[5] != 200:
		print("FAIL map_full data"); return false
	print("PASS map_full"); return true


func _test_map_delta() -> bool:
	var entries := [
		{"gx": -1, "gy": 2, "state": 100},
		{"gx": 300, "gy": -400, "state": 255},
	]
	var payload := OrionMessages.Encode_Map_Delta(777, entries)
	if payload.size() != 6 + 18:
		print("FAIL map_delta size"); return false
	var dec := OrionMessages.Decode_Map_Delta(payload)
	if not dec.ok:
		print("FAIL map_delta decode: ", dec.error); return false
	if dec.count != 2 or dec.entries.size() != 2:
		print("FAIL map_delta count"); return false
	var e0: Dictionary = dec.entries[0]
	var e1: Dictionary = dec.entries[1]
	if e0.gx != -1 or e0.gy != 2 or e0.state != 100:
		print("FAIL map_delta e0: ", e0); return false
	if e1.gx != 300 or e1.gy != -400 or e1.state != 255:
		print("FAIL map_delta e1: ", e1); return false
	print("PASS map_delta"); return true


func _test_manual_control() -> bool:
	var payload := OrionMessages.Encode_Manual_Control(4, -50)
	var dec := OrionMessages.Decode_Manual_Control(payload)
	if not dec.ok or dec.action != 4 or dec.param != -50:
		print("FAIL manual_control: ", dec); return false
	print("PASS manual_control"); return true


func _test_task_set() -> bool:
	var missions := [
		{"type": 0, "x": 12.5, "y": -3.25},
		{"type": 0, "x": 0.0, "y": 99.99},
	]
	var payload := OrionMessages.Encode_Task_Set(missions)
	if payload.size() != 1 + 18:
		print("FAIL task_set size"); return false
	if payload[0] != 2:
		print("FAIL task_set count"); return false
	var dec := OrionMessages.Decode_Task_Set(payload)
	if not dec.ok or dec.count != 2 or dec.missions.size() != 2:
		print("FAIL task_set decode: ", dec); return false
	var m0: Dictionary = dec.missions[0]
	var m1: Dictionary = dec.missions[1]
	if m0.type != 0 or absf(m0.x - 12.5) > 0.0001 or absf(m0.y - (-3.25)) > 0.0001:
		print("FAIL task_set m0: ", m0); return false
	if m1.type != 0 or absf(m1.y - 99.99) > 0.0001:
		print("FAIL task_set m1: ", m1); return false
	print("PASS task_set"); return true


func _test_build_cmd() -> bool:
	var cmd := MessageBuilder.build_manual_forward(80)
	var frame := OrionMessages.Build_Cmd(cmd)
	if frame.is_empty():
		print("FAIL build_cmd empty"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	if not dec.ok or dec.msgid != 4 or dec.sysid != 200 or dec.compid != 200:
		print("FAIL build_cmd frame: ", dec); return false
	var mc := OrionMessages.Decode_Manual_Control(dec.payload)
	if mc.action != ProtocolDef.ACTION_FORWARD or mc.param != 80:
		print("FAIL build_cmd payload: ", mc); return false

	var cancel := MessageBuilder.build_auto_cancel()
	var frame2 := OrionMessages.Build_Cmd(cancel)
	var dec2 := OrionFrame.Decode_Frame(frame2)
	var ts := OrionMessages.Decode_Task_Set(dec2.payload)
	if ts.count != 0 or not ts.missions.is_empty():
		print("FAIL build_cmd cancel: ", ts); return false
	print("PASS build_cmd"); return true


func _test_parser_dispatch() -> bool:
	# pose 帧 → parse_orion_frame
	var pose_frame := OrionFrame.Encode_Frame(1, 1, 1, OrionMessages.Encode_Pose(1, 2.0, 3.0, 0, 0, 0))
	var r := MessageParser.parse_orion_frame(pose_frame)
	if not r.ok or r.msgid != 1 or absf(r.data.x - 2.0) > 0.0001:
		print("FAIL parser pose: ", r); return false
	# map_full 帧 → chunk 坐标换算（origin=-256 → chunk_x=-1）
	var data := PackedByteArray(); data.resize(65536)
	var full_frame := OrionFrame.Encode_Frame(2, 1, 1, OrionMessages.Encode_Map_Full(0, -256, 256, 256, 256, 0.5, data))
	var r2 := MessageParser.parse_orion_frame(full_frame)
	if not r2.ok or r2.data.chunk_x != -1 or r2.data.chunk_y != 1:
		print("FAIL parser map_full chunk: ", r2); return false
	# 未知 msgid
	var bad := OrionFrame.Encode_Frame(99, 1, 1, PackedByteArray([0]))
	if MessageParser.parse_orion_frame(bad).ok:
		print("FAIL parser unknown msgid accepted"); return false
	print("PASS parser_dispatch"); return true


func _test_llm_string_type() -> bool:
	# LLM 输出字符串 mission type "goto" → 归一化为 0，正常编码下发
	var llm_cmd := {"cmd": "auto", "action": "push", "missions": [{"type": "goto", "x": 3.0, "y": 5.0}]}
	var orion_cmd := MessageBuilder.build_from_llm(llm_cmd)
	if orion_cmd.is_empty() or orion_cmd.msgid != ProtocolDef.MSGID_TASK_SET:
		print("FAIL build_from_llm auto: ", orion_cmd); return false
	var frame := OrionMessages.Build_Cmd(orion_cmd)
	if frame.is_empty():
		print("FAIL llm string type frame empty"); return false
	var dec := OrionFrame.Decode_Frame(frame)
	var ts := OrionMessages.Decode_Task_Set(dec.payload)
	if ts.count != 1 or ts.missions[0].type != 0:
		print("FAIL llm string type normalized: ", ts); return false
	if absf(ts.missions[0].x - 3.0) > 0.0001 or absf(ts.missions[0].y - 5.0) > 0.0001:
		print("FAIL llm mission coords"); return false
	# 混合指令顺序：auto push 在 manual forward 之前，逐条转换保持顺序
	var mixed := [
		{"cmd": "auto", "action": "push", "missions": [{"type": "goto", "x": 1.0, "y": 1.0}]},
		{"cmd": "manual", "action": "forward", "speed": 60},
	]
	var first := MessageBuilder.build_from_llm(mixed[0])
	if first.msgid != ProtocolDef.MSGID_TASK_SET:
		print("FAIL mixed first: ", first); return false
	var second := MessageBuilder.build_from_llm(mixed[1])
	if second.msgid != ProtocolDef.MSGID_MANUAL_CONTROL or second.action != ProtocolDef.ACTION_FORWARD or second.param != 60:
		print("FAIL mixed second: ", second); return false
	print("PASS llm_string_type"); return true


# ─── 大端字节序断言（与 Rust 端字节逐一比对）──────────────────────

func _test_endianness() -> bool:
	# 1) 帧 len 大端：payload 5 → [00 00 00 05]；msgid 3 → [00 03]
	var f := OrionFrame.Encode_Frame(3, 200, 1, PackedByteArray([1, 2, 3, 4, 5]))
	var len_bytes := f.slice(1, 5)
	if len_bytes != PackedByteArray([0x00, 0x00, 0x00, 0x05]):
		print("FAIL frame len BE bytes: ", len_bytes); return false
	if f.slice(8, 10) != PackedByteArray([0x00, 0x03]):
		print("FAIL frame msgid BE bytes"); return false

	# 2) 模拟真实 Rust 大端帧（map_full 65556）→ Decode_Frame 必须正确读出
	var rust_frame := PackedByteArray()
	rust_frame.resize(12 + 65556)
	rust_frame[0] = 0x4F
	# len = 65556 大端字节 [00 01 00 14]
	rust_frame[1] = 0x00; rust_frame[2] = 0x01; rust_frame[3] = 0x00; rust_frame[4] = 0x14
	rust_frame[5] = 0; rust_frame[6] = 0; rust_frame[7] = 1
	rust_frame[8] = 0x00; rust_frame[9] = 0x02  # msgid = 2 (MAP_FULL)
	var dec := OrionFrame.Decode_Frame(rust_frame)
	if not dec.ok:
		print("FAIL rust BE frame decode: ", dec.error); return false
	if dec.msgid != 2 or dec.payload.size() != 65556:
		print("FAIL rust BE frame fields"); return false

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

	# 6) task_set x=12.5 → 0x41480000 → [41 48 00 00]
	var ts := OrionMessages.Encode_Task_Set([{"type": 0, "x": 12.5, "y": 0.0}])
	if ts.slice(2, 6) != PackedByteArray([0x41, 0x48, 0x00, 0x00]):
		print("FAIL task_set f32 BE: ", ts.slice(2, 6)); return false

	print("PASS endianness (BE bytes match Rust)"); return true
