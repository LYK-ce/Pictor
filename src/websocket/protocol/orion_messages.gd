## Presented by KeJi
## Date ： 2026-09-01
## Modified Date ： 2026-10-29
##
## OrionMessages — Orion 协议 5 种消息 payload 编解码
## 规范文档：docs/orion_protocol.md
## 全部大端（使用 OrionFrame 的 Read_*/Write_* helper，Godot 原生 API 为小端）。
## Task 21：地图数据语义 = log-odds i8（−8~+8，u8 位模式直传）；三态由显示层按阈值 ±6 派生。
##
## 消息清单：
##   msgid 1 ORION_POSE          38B        (u32 time_boot_ms + 6×f32 + valid u8 + sub_gx i32 + sub_gy i32 + rtk_fixed u8)
##   msgid 2 ORION_MAP_FULL      20B 头 + data（log-odds i8，−8~+8）
##   msgid 3 ORION_MAP_DELTA     6B + 9B/entry（delta i8 差分，累加式）
##   msgid 4 ORION_MANUAL_CONTROL 3B        (u8 action + i16 param)
##   msgid 5 ORION_TASK_SET      1B + 9B/mission（task_36：删名单段，一帧一车）
## 下行命令组装入口：Build_Cmd（cmd_send 的 Dictionary → 完整帧）

class_name OrionMessages
extends RefCounted


# ─── ORION_POSE (msgid 1) — 38B（v4：+ rtk_fixed；v3：+ z 高度；v2：+ valid/sub_gx/sub_gy 意图字段）────

static func Encode_Pose(time_boot_ms: int, x: float, y: float, vx: float, vy: float, yaw: float, valid := false, sub_gx := 0, sub_gy := 0, z := 0.0, rtk_fixed := false) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(38)
	OrionFrame.Write_U32_BE(buf, 0, time_boot_ms)
	OrionFrame.Write_F32_BE(buf, 4, x)
	OrionFrame.Write_F32_BE(buf, 8, y)
	OrionFrame.Write_F32_BE(buf, 12, z)
	OrionFrame.Write_F32_BE(buf, 16, vx)
	OrionFrame.Write_F32_BE(buf, 20, vy)
	OrionFrame.Write_F32_BE(buf, 24, yaw)
	buf[28] = 1 if valid else 0
	OrionFrame.Write_S32_BE(buf, 29, sub_gx)
	OrionFrame.Write_S32_BE(buf, 33, sub_gy)
	buf[37] = 1 if rtk_fixed else 0
	return buf


## 返回: { ok, time_boot_ms, x, y, z, vx, vy, yaw, valid, sub_gx, sub_gy, rtk_fixed, error }
static func Decode_Pose(payload: PackedByteArray) -> Dictionary:
	if payload.size() != 38:
		return _Fail("pose payload size mismatch: %d (expect 38)" % payload.size())
	return {
		"ok": true,
		"time_boot_ms": OrionFrame.Read_U32_BE(payload, 0),
		"x": OrionFrame.Read_F32_BE(payload, 4),
		"y": OrionFrame.Read_F32_BE(payload, 8),
		"z": OrionFrame.Read_F32_BE(payload, 12),
		"vx": OrionFrame.Read_F32_BE(payload, 16),
		"vy": OrionFrame.Read_F32_BE(payload, 20),
		"yaw": OrionFrame.Read_F32_BE(payload, 24),
		"valid": payload[28] != 0,
		"sub_gx": OrionFrame.Read_S32_BE(payload, 29),
		"sub_gy": OrionFrame.Read_S32_BE(payload, 33),
		"rtk_fixed": payload[37] != 0,
		"error": "",
	}


# ─── ORION_MAP_FULL (msgid 2) — 20B 头 + data ─────────────────

static func Encode_Map_Full(time_boot_ms: int, origin_gx: int, origin_gy: int, width: int, height: int, resolution: float, data: PackedByteArray) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(20 + data.size())
	OrionFrame.Write_U32_BE(buf, 0, time_boot_ms)
	OrionFrame.Write_S32_BE(buf, 4, origin_gx)
	OrionFrame.Write_S32_BE(buf, 8, origin_gy)
	OrionFrame.Write_U16_BE(buf, 12, width)
	OrionFrame.Write_U16_BE(buf, 14, height)
	OrionFrame.Write_F32_BE(buf, 16, resolution)
	for i in range(data.size()):
		buf[20 + i] = data[i]
	return buf


## 返回: { ok, time_boot_ms, origin_gx, origin_gy, width, height, resolution, data, error }
static func Decode_Map_Full(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 20:
		return _Fail("map_full payload too small: %d" % payload.size())
	var width := OrionFrame.Read_U16_BE(payload, 12)
	var height := OrionFrame.Read_U16_BE(payload, 14)
	var data_size := width * height
	if payload.size() < 20 + data_size:
		return _Fail("map_full data truncated: need %d have %d" % [20 + data_size, payload.size()])
	return {
		"ok": true,
		"time_boot_ms": OrionFrame.Read_U32_BE(payload, 0),
		"origin_gx": OrionFrame.Read_S32_BE(payload, 4),
		"origin_gy": OrionFrame.Read_S32_BE(payload, 8),
		"width": width,
		"height": height,
		"resolution": OrionFrame.Read_F32_BE(payload, 16),
		"data": payload.slice(20, 20 + data_size),
		"error": "",
	}


# ─── ORION_MAP_DELTA (msgid 3) — 6B + 9B/entry ────────────────

static func Encode_Map_Delta(time_boot_ms: int, entries: Array) -> PackedByteArray:
	var count := entries.size()
	if count > 65535:
		printerr("[OrionMessages] map_delta entries exceed u16 max: ", count, " — truncated")
		count = 65535
	var buf := PackedByteArray()
	buf.resize(6 + 9 * count)
	OrionFrame.Write_U32_BE(buf, 0, time_boot_ms)
	OrionFrame.Write_U16_BE(buf, 4, count)
	var off := 6
	for i in range(count):
		var e = entries[i]
		OrionFrame.Write_S32_BE(buf, off, e.get("gx", 0))
		OrionFrame.Write_S32_BE(buf, off + 4, e.get("gy", 0))
		var delta: int = clampi(e.get("delta", 0), -127, 127)  # 防御：i8 范围
		buf[off + 8] = delta & 0xFF                             # i8 → u8 位模式（−8 → 0xF8）
		off += 9
	return buf


## 返回: { ok, time_boot_ms, count, entries: Array[{gx, gy, delta}], error }（delta 为 i8 差分值）
static func Decode_Map_Delta(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 6:
		return _Fail("map_delta payload too small: %d" % payload.size())
	var count := OrionFrame.Read_U16_BE(payload, 4)
	if payload.size() < 6 + 9 * count:
		return _Fail("map_delta entries truncated: need %d have %d" % [6 + 9 * count, payload.size()])
	var entries: Array = []
	var off := 6
	for i in range(count):
		var b: int = payload[off + 8]
		entries.append({
			"gx": OrionFrame.Read_S32_BE(payload, off),
			"gy": OrionFrame.Read_S32_BE(payload, off + 4),
			"delta": b if b <= 127 else b - 256,   # u8 → i8 有符号解释（248 → −8）
		})
		off += 9
	return {"ok": true, "time_boot_ms": OrionFrame.Read_U32_BE(payload, 0), "count": count, "entries": entries, "error": ""}


# ─── ORION_MANUAL_CONTROL (msgid 4) — 3B ──────────────────────

static func Encode_Manual_Control(action: int, param: int) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(3)
	buf[0] = action
	OrionFrame.Write_S16_BE(buf, 1, param)
	return buf


## 返回: { ok, action, param, error }
static func Decode_Manual_Control(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 3:
		return _Fail("manual_control payload too small: %d" % payload.size())
	return {"ok": true, "action": payload[0], "param": OrionFrame.Read_S16_BE(payload, 1), "error": ""}


# ─── ORION_TASK_SET (msgid 5) — 任务队列整体替换（一帧一车）────────────
## 布局（大端）：mission_count u8 + missions[mission_count] × 9B（type u8 | x f32 | y f32）
## 总长 = 1 + 9 × mission_count（严格；多 1 字节也拒）
## 语义（task_36 §12.3.4）：mission_count == 0 → 取消（空队列替换，停车待命）；> 0 → 逐条入队
## task_36 §十一 #27 / #28：协同上移到指挥层 —— 地面站逐车算点、逐车单独发帧，
## 每帧 missions[0] 就是"该车自己的点"，载荷里不再有名单段（旧的 peer 名单已删）。

## missions: Array[{type, x, y}]；type 只允许 {MISSION_TYPE_GOTO, MISSION_TYPE_FOLLOW}（其余降级并告警，见下）
static func Encode_Task_Set(missions: Array) -> PackedByteArray:
	var m_count := missions.size()
	if m_count > 255:
		printerr("[OrionMessages] task_set missions exceed u8 max: ", m_count, " — truncated")
		m_count = 255
	var buf := PackedByteArray()
	buf.resize(1 + 9 * m_count)
	buf[0] = m_count
	var off := 1
	for i in range(m_count):
		var mi = missions[i]
		# mission type 归一化：LLM 可能输出字符串 "goto"/"follow"（防御性）
		var mt = mi.get("type", ProtocolDef.MISSION_TYPE_GOTO)
		if mt is String:
			mt = ProtocolDef.Mission_Type_From(mt)
		# 车端认 type ∈ {0 Goto, 2 Follow}：其余类型会被 command_decode 丢弃（task_36 §12.3.4）。
		# 静默丢任务比"降级到锚点"更危险，故此处强制降级并告警（Circle 已随 §十一 #27 废弃）。
		if int(mt) != ProtocolDef.MISSION_TYPE_GOTO and int(mt) != ProtocolDef.MISSION_TYPE_FOLLOW:
			printerr("[OrionMessages] mission type ", int(mt),
					" unsupported (only {0,2}): Goto/Follow, coerced to 0")
			mt = ProtocolDef.MISSION_TYPE_GOTO
		buf[off] = int(mt)
		OrionFrame.Write_F32_BE(buf, off + 1, mi.get("x", 0.0))
		OrionFrame.Write_F32_BE(buf, off + 5, mi.get("y", 0.0))
		off += 9
	return buf


## 返回: { ok, mission_count, missions: Array[{type, x, y}], error }
## 校验：空 payload → fail（取消帧也必须是 1 字节 mission_count=0）；
##      长度必须严格 == 1 + 9×mission_count（带成员段的旧布局帧在此被拒）
static func Decode_Task_Set(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return _Fail("task_set payload empty (need at least 1 byte)")
	var m_count := payload[0]
	if payload.size() != 1 + 9 * m_count:
		return _Fail("task_set size mismatch: need %d have %d" % [1 + 9 * m_count, payload.size()])
	var missions: Array = []
	var off := 1
	for i in range(m_count):
		missions.append({
			"type": payload[off],
			"x": OrionFrame.Read_F32_BE(payload, off + 1),
			"y": OrionFrame.Read_F32_BE(payload, off + 5),
		})
		off += 9
	return {"ok": true, "mission_count": m_count, "missions": missions, "error": ""}


# ─── 下行命令组装（cmd_send 的 Dictionary → 完整帧）────────────

## cmd 由 MessageBuilder 构造，格式: { "msgid": int, ...消息字段 }
## 发送方身份：v2 终端上行 = 空 sysid（sysid_len=0）+ compid = COMPID_TERMINAL
static func Build_Cmd(cmd: Dictionary) -> PackedByteArray:
	var msgid: int = cmd.get("msgid", -1)
	var payload := PackedByteArray()
	match msgid:
		ProtocolDef.MSGID_MAP_FULL:
			# 阶段 2：终端返还合并全量（车端 handle_map_full 严格校验元数据）
			payload = Encode_Map_Full(
				cmd.get("time_boot_ms", Time.get_ticks_msec() & 0xFFFFFFFF),
				cmd.get("origin_gx", 0),
				cmd.get("origin_gy", 0),
				cmd.get("width", ProtocolDef.MAP_WIDTH),
				cmd.get("height", ProtocolDef.MAP_HEIGHT),
				cmd.get("resolution", ProtocolDef.MAP_RESOLUTION),
				cmd.get("data", PackedByteArray()),
			)
		ProtocolDef.MSGID_MANUAL_CONTROL:
			payload = Encode_Manual_Control(cmd.get("action", ProtocolDef.ACTION_STOP), cmd.get("param", 0))
		ProtocolDef.MSGID_TASK_SET:
			payload = Encode_Task_Set(cmd.get("missions", []))
		_:
			printerr("[OrionMessages] unknown cmd msgid: ", msgid)
			return PackedByteArray()
	return OrionFrame.Encode_Frame(msgid, PackedByteArray(), ProtocolDef.COMPID_TERMINAL, payload)


static func _Fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
