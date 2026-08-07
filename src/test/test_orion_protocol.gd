extends SceneTree

## Orion 协议编解码 roundtrip 测试（headless）
## 用法: godot --headless --path <项目> -s <本脚本路径>

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
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


func _test_frame() -> bool:
	var payload := PackedByteArray([1, 2, 3, 4, 5])
	var frame := OrionFrame.Encode_Frame(3, 200, 1, payload)
	if frame[0] != 0x4F:
		print("FAIL magic"); return false
	if frame.decode_u32(1) != 5:
		print("FAIL len"); return false
	if frame[6] != 200 or frame[7] != 1:
		print("FAIL sysid/compid"); return false
	if frame.decode_u16(8) != 3:
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
