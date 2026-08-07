## Presented by KeJi
## Date ： 2026-08-07
##
## OrionMessages — Orion 协议 5 种消息 payload 编解码
## 规范文档：docs/orion_protocol.md
## 全部大端。地图状态编码：0=free / 100=occupied / 255=unknown（与内部存储统一，零映射直传）。
##
## 消息清单：
##   msgid 1 ORION_POSE          24B        (u32 time_boot_ms + 5×f32)
##   msgid 2 ORION_MAP_FULL      20B 头 + data
##   msgid 3 ORION_MAP_DELTA     6B + 9B/entry
##   msgid 4 ORION_MANUAL_CONTROL 3B        (u8 action + i16 param)
##   msgid 5 ORION_TASK_SET      1B + 9B/mission
## 下行命令组装入口：Build_Cmd（cmd_send 的 Dictionary → 完整帧）

class_name OrionMessages
extends RefCounted


# ─── ORION_POSE (msgid 1) — 24B ──────────────────────────────

static func Encode_Pose(time_boot_ms: int, x: float, y: float, vx: float, vy: float, yaw: float) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(24)
	buf.encode_u32(0, time_boot_ms)
	buf.encode_float(4, x)
	buf.encode_float(8, y)
	buf.encode_float(12, vx)
	buf.encode_float(16, vy)
	buf.encode_float(20, yaw)
	return buf


## 返回: { ok, time_boot_ms, x, y, vx, vy, yaw, error }
static func Decode_Pose(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 24:
		return _Fail("pose payload too small: %d" % payload.size())
	return {
		"ok": true,
		"time_boot_ms": payload.decode_u32(0),
		"x": payload.decode_float(4),
		"y": payload.decode_float(8),
		"vx": payload.decode_float(12),
		"vy": payload.decode_float(16),
		"yaw": payload.decode_float(20),
		"error": "",
	}


# ─── ORION_MAP_FULL (msgid 2) — 20B 头 + data ─────────────────

static func Encode_Map_Full(time_boot_ms: int, origin_gx: int, origin_gy: int, width: int, height: int, resolution: float, data: PackedByteArray) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(20 + data.size())
	buf.encode_u32(0, time_boot_ms)
	buf.encode_s32(4, origin_gx)
	buf.encode_s32(8, origin_gy)
	buf.encode_u16(12, width)
	buf.encode_u16(14, height)
	buf.encode_float(16, resolution)
	for i in range(data.size()):
		buf[20 + i] = data[i]
	return buf


## 返回: { ok, time_boot_ms, origin_gx, origin_gy, width, height, resolution, data, error }
static func Decode_Map_Full(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 20:
		return _Fail("map_full payload too small: %d" % payload.size())
	var width := payload.decode_u16(12)
	var height := payload.decode_u16(14)
	var data_size := width * height
	if payload.size() < 20 + data_size:
		return _Fail("map_full data truncated: need %d have %d" % [20 + data_size, payload.size()])
	return {
		"ok": true,
		"time_boot_ms": payload.decode_u32(0),
		"origin_gx": payload.decode_s32(4),
		"origin_gy": payload.decode_s32(8),
		"width": width,
		"height": height,
		"resolution": payload.decode_float(16),
		"data": payload.slice(20, 20 + data_size),
		"error": "",
	}


# ─── ORION_MAP_DELTA (msgid 3) — 6B + 9B/entry ────────────────

static func Encode_Map_Delta(time_boot_ms: int, entries: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(6 + 9 * entries.size())
	buf.encode_u32(0, time_boot_ms)
	buf.encode_u16(4, entries.size())
	var off := 6
	for e in entries:
		buf.encode_s32(off, e.get("gx", 0))
		buf.encode_s32(off + 4, e.get("gy", 0))
		buf[off + 8] = e.get("state", ProtocolDef.CELL_FREE)
		off += 9
	return buf


## 返回: { ok, time_boot_ms, count, entries: Array[{gx, gy, state}], error }
static func Decode_Map_Delta(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 6:
		return _Fail("map_delta payload too small: %d" % payload.size())
	var count := payload.decode_u16(4)
	if payload.size() < 6 + 9 * count:
		return _Fail("map_delta entries truncated: need %d have %d" % [6 + 9 * count, payload.size()])
	var entries: Array = []
	var off := 6
	for i in range(count):
		entries.append({
			"gx": payload.decode_s32(off),
			"gy": payload.decode_s32(off + 4),
			"state": payload[off + 8],
		})
		off += 9
	return {"ok": true, "time_boot_ms": payload.decode_u32(0), "count": count, "entries": entries, "error": ""}


# ─── ORION_MANUAL_CONTROL (msgid 4) — 3B ──────────────────────

static func Encode_Manual_Control(action: int, param: int) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(3)
	buf[0] = action
	buf.encode_s16(1, param)
	return buf


## 返回: { ok, action, param, error }
static func Decode_Manual_Control(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 3:
		return _Fail("manual_control payload too small: %d" % payload.size())
	return {"ok": true, "action": payload[0], "param": payload.decode_s16(1), "error": ""}


# ─── ORION_TASK_SET (msgid 5) — 1B + 9B/mission ───────────────

static func Encode_Task_Set(missions: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(1 + 9 * missions.size())
	buf[0] = missions.size()
	var off := 1
	for m in missions:
		buf[off] = m.get("type", ProtocolDef.MISSION_TYPE_GOTO)
		buf.encode_float(off + 1, m.get("x", 0.0))
		buf.encode_float(off + 5, m.get("y", 0.0))
		off += 9
	return buf


## 返回: { ok, count, missions: Array[{type, x, y}], error }
static func Decode_Task_Set(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 1:
		return _Fail("task_set payload too small")
	var count := payload[0]
	if payload.size() < 1 + 9 * count:
		return _Fail("task_set missions truncated: need %d have %d" % [1 + 9 * count, payload.size()])
	var missions: Array = []
	var off := 1
	for i in range(count):
		missions.append({
			"type": payload[off],
			"x": payload.decode_float(off + 1),
			"y": payload.decode_float(off + 5),
		})
		off += 9
	return {"ok": true, "count": count, "missions": missions, "error": ""}


# ─── 下行命令组装（cmd_send 的 Dictionary → 完整帧）────────────

## cmd 由 MessageBuilder 构造，格式: { "msgid": int, ...消息字段 }
## 发送方身份固定：sysid = SYSID_TERMINAL, compid = COMPID_TERMINAL
static func Build_Cmd(cmd: Dictionary) -> PackedByteArray:
	var msgid: int = cmd.get("msgid", -1)
	var payload := PackedByteArray()
	match msgid:
		ProtocolDef.MSGID_MANUAL_CONTROL:
			payload = Encode_Manual_Control(cmd.get("action", ProtocolDef.ACTION_STOP), cmd.get("param", 0))
		ProtocolDef.MSGID_TASK_SET:
			payload = Encode_Task_Set(cmd.get("missions", []))
		_:
			printerr("[OrionMessages] unknown cmd msgid: ", msgid)
			return PackedByteArray()
	return OrionFrame.Encode_Frame(msgid, ProtocolDef.SYSID_TERMINAL, ProtocolDef.COMPID_TERMINAL, payload)


static func _Fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
