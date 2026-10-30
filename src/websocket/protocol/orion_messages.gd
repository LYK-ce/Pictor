## Presented by KeJi
## Date ： 2026-09-01
## Modified Date ： 2026-10-30
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
##   msgid 5 ORION_TASK_SET      1B + 变长/条（0/2 = 9B、3 = 13B；task_41 §3.2）
##   msgid 7 ORION_ASSIST_REQUEST 8B        (x f32 BE + y f32 BE；task_41 §5.3，仅上行)
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
## 布局（大端，task_41 §3.2 起**按 type 变长**）：
##   mission_count u8 | mission[0] | … | mission[count-1]，总长 = 1 + Σlen
##   type 0 Goto        : type u8 | x  f32 BE | y f32 BE                 = 9 B
##   type 2 Follow      : type u8 | x  f32 BE | y f32 BE                 = 9 B
##   type 3 Containment : type u8 | cx f32 BE | cy f32 BE | half f32 BE  = 13 B
## 语义（task_36 §12.3.4）：mission_count == 0 → 取消（空队列替换，停车待命）；> 0 → 逐条入队
## 未知 type（含退役的 1 = Circle）无法确定长度 → **整帧拒**（解码）/ **整帧不发**（编码）
## task_36 §十一 #27 / #28：协同上移到指挥层 —— 地面站逐车算点、逐车单独发帧，
## 每帧 missions[0] 就是"该车自己的点"，载荷里不再有名单段（旧的 peer 名单已删）。


## 记录长度表（含 type 字节；task_41 §3.2）。0 = 未知 type → 整帧不编码、不发帧
static func _Mission_Wire_Len(mt: int) -> int:
	match mt:
		ProtocolDef.MISSION_TYPE_GOTO, ProtocolDef.MISSION_TYPE_FOLLOW:
			return 9
		ProtocolDef.MISSION_TYPE_CONTAINMENT:
			return 13
		_:
			return 0


## missions: Array[{type, x, y, half_side}]；type 只允许 {0 Goto, 2 Follow, 3 Containment}
## 未知 type（含退役的 1）或 type=3 的非法 `half_side` → printerr + **返回空数组（不降级、不发帧）**。
## 空数组由 `Build_Cmd` 转成空帧，`kernel_bridge` 已有 `frame.is_empty()` 短路（不会真的发出去）。
static func Encode_Task_Set(missions: Array) -> PackedByteArray:
	# ① 先归一化 type + 查长度表 + 校验 half_side（一遍扫完，出错即整帧放弃）
	var items: Array = []   # [{type:int, mi:Dictionary, len:int}]
	var total := 1
	for i in range(missions.size()):
		if items.size() >= 255:
			printerr("[OrionMessages] task_set missions exceed u8 max: ", missions.size(), " — truncated")
			break
		var mi: Dictionary = missions[i]
		# mission type 归一化：LLM 可能输出字符串 "goto"/"follow"/"containment"（防御性）
		var mty_v: Variant = mi.get("type", ProtocolDef.MISSION_TYPE_GOTO)
		var mty: int = ProtocolDef.Mission_Type_From(mty_v) if (mty_v is String) else int(mty_v)
		var ln := _Mission_Wire_Len(mty)
		if ln == 0:
			printerr("[OrionMessages] mission type ", mty,
					" unsupported (only {0,2,3}): Goto/Follow/Containment → refuse to encode（不发帧）")
			return PackedByteArray()
		if mty == ProtocolDef.MISSION_TYPE_CONTAINMENT:
			var mh: Variant = mi.get("half_side", null)
			if not ((mh is float) or (mh is int)) or not is_finite(float(mh)) or float(mh) <= 0.0:
				printerr("[OrionMessages] containment half_side invalid: ", mh,
						"（必须有限且 > 0）→ refuse to encode（不发帧）")
				return PackedByteArray()
		items.append({"type": mty, "mi": mi, "len": ln})
		total += ln
	# ② 按 type 变长写（先 resize 再写，避免越界）
	var buf := PackedByteArray()
	buf.resize(total)
	buf[0] = items.size()
	var off := 1
	for it in items:
		var mt: int = int(it["type"])
		var mi2: Dictionary = it["mi"]
		var ln2: int = int(it["len"])
		buf[off] = mt
		OrionFrame.Write_F32_BE(buf, off + 1, mi2.get("x", 0.0))
		OrionFrame.Write_F32_BE(buf, off + 5, mi2.get("y", 0.0))
		if ln2 == 13:
			OrionFrame.Write_F32_BE(buf, off + 9, float(mi2.get("half_side", 0.0)))
		off += ln2
	return buf


## 返回: { ok, mission_count, missions: Array[{type, x, y, half_side}], error }
## 校验：空 payload → fail（取消帧也必须是 1 字节 mission_count=0）；
##      逐条按 type 取变长；未知 type / 截断 / 末尾偏移 != payload 长度 → fail（**整帧拒**）
static func Decode_Task_Set(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return _Fail("task_set payload empty (need at least 1 byte)")
	var m_count := payload[0]
	var missions: Array = []
	var off := 1
	for i in range(m_count):
		if off >= payload.size():
			return _Fail("task_set truncated at mission %d: off %d size %d" % [i, off, payload.size()])
		var mt := payload[off]
		var ln := _Mission_Wire_Len(mt)
		if ln == 0:
			return _Fail("task_set unknown mission type %d at mission %d" % [mt, i])
		if off + ln > payload.size():
			return _Fail("task_set truncated mission %d: need %d have %d" % [i, off + ln, payload.size()])
		var one := {
			"type": mt,
			"x": OrionFrame.Read_F32_BE(payload, off + 1),
			"y": OrionFrame.Read_F32_BE(payload, off + 5),
			"half_side": 0.0,
		}
		if mt == ProtocolDef.MISSION_TYPE_CONTAINMENT:
			var mh := OrionFrame.Read_F32_BE(payload, off + 9)
			if not is_finite(mh) or mh <= 0.0:
				return _Fail("task_set containment half_side invalid: %f" % mh)
			one["half_side"] = mh
		missions.append(one)
		off += ln
	if off != payload.size():
		return _Fail("task_set size mismatch: consumed %d have %d" % [off, payload.size()])
	return {"ok": true, "mission_count": m_count, "missions": missions, "error": ""}


# ─── ORION_ASSIST_REQUEST (msgid 7) — 上行协助请求（8B，task_41 §5.3）───────
## 返回: { ok, x, y, error }；长度**严格 8 B**、非有限值拒（与 Rust `decode_assist_request` 同口径）
## 单向（UAV → 地面站），Pictor 只解不发：本端没有 Encode_Assist_Request。
static func Decode_Assist_Request(payload: PackedByteArray) -> Dictionary:
	if payload.size() != 8:
		return _Fail("assist_request payload size mismatch: %d (expect 8)" % payload.size())
	var ax := OrionFrame.Read_F32_BE(payload, 0)
	var ay := OrionFrame.Read_F32_BE(payload, 4)
	if not is_finite(ax) or not is_finite(ay):
		return _Fail("assist_request non-finite coordinates: %f,%f" % [ax, ay])
	return {"ok": true, "x": ax, "y": ay, "error": ""}


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
			if payload.is_empty():
				# 未知 type / 非法 half_side：编码阶段已 printerr，这里**不发帧**
				printerr("[OrionMessages] task_set 编码失败（未知 type / 非法 half_side）→ 不发帧")
				return PackedByteArray()
		_:
			printerr("[OrionMessages] unknown cmd msgid: ", msgid)
			return PackedByteArray()
	return OrionFrame.Encode_Frame(msgid, PackedByteArray(), ProtocolDef.COMPID_TERMINAL, payload)


static func _Fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
