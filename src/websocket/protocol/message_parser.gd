## Presented by KeJi
## Date ： 2026-08-11
##
## MessageParser — 上行消息解析器（小车 → PC）
## 纯静态方法，无状态。
## - JSON 文本帧：仅处理过渡期 hello（其余 JSON 消息忽略）
## - 二进制帧：Orion 帧解析（OrionFrame.Decode_Frame + 按 msgid 分发 payload）

class_name MessageParser
extends RefCounted


# ─── JSON 文本消息（过渡期 hello）─────────────────────────────

## 解析 JSON 文本消息。
## 返回: { ok: bool, type: String, data: Dictionary, error: String }
static func parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return _fail("bad JSON: " + text.left(100))

	var data = json.get_data()
	if not data is Dictionary:
		return _fail("not a JSON object")

	var msg_type: String = data.get("type", "")
	if msg_type.is_empty():
		return _fail("missing type field")

	return {"ok": true, "type": msg_type, "data": data, "error": ""}


# ─── Orion 二进制帧 ─────────────────────────────────────────

## 解析 Orion 帧，按 msgid 分发为结构化结果。
## 返回: { ok: bool, msgid: int, data: Dictionary, error: String }
## data 按消息类型填充：
##   MSGID_POSE     → { time_boot_ms, x, y, vx, vy, yaw }
##   MSGID_MAP_FULL → { chunk_x, chunk_y, cells, width, height, resolution }
##   MSGID_MAP_DELTA→ { voxels: [{gx, gy, delta}] }（delta 为 i8 差分，累加式）
static func parse_orion_frame(pkt: PackedByteArray) -> Dictionary:
	var frame := OrionFrame.Decode_Frame(pkt)
	if not frame.ok:
		return _fail(frame.error)

	match frame.msgid:
		ProtocolDef.MSGID_POSE:
			var pose := OrionMessages.Decode_Pose(frame.payload)
			if not pose.ok:
				return _fail(pose.error)
			return {"ok": true, "msgid": frame.msgid, "data": pose, "error": ""}

		ProtocolDef.MSGID_MAP_FULL:
			var full := OrionMessages.Decode_Map_Full(frame.payload)
			if not full.ok:
				return _fail(full.error)
			# origin 为 chunk 原点全局网格坐标 → 换算为 chunk 坐标
			var chunk_x := floori(full.origin_gx / float(ProtocolDef.CHUNK_SIZE))
			var chunk_y := floori(full.origin_gy / float(ProtocolDef.CHUNK_SIZE))
			return {
				"ok": true,
				"msgid": frame.msgid,
				"data": {
					"chunk_x": chunk_x,
					"chunk_y": chunk_y,
					"cells": full.data,
					"width": full.width,
					"height": full.height,
					"resolution": full.resolution,
				},
				"error": "",
			}

		ProtocolDef.MSGID_MAP_DELTA:
			var delta := OrionMessages.Decode_Map_Delta(frame.payload)
			if not delta.ok:
				return _fail(delta.error)
			return {
				"ok": true,
				"msgid": frame.msgid,
				"data": {"voxels": delta.entries},
				"error": "",
			}

		ProtocolDef.MSGID_MANUAL_CONTROL:
			var mc := OrionMessages.Decode_Manual_Control(frame.payload)
			if not mc.ok:
				return _fail(mc.error)
			return {"ok": true, "msgid": frame.msgid, "data": mc, "error": ""}

		ProtocolDef.MSGID_TASK_SET:
			var ts := OrionMessages.Decode_Task_Set(frame.payload)
			if not ts.ok:
				return _fail(ts.error)
			return {"ok": true, "msgid": frame.msgid, "data": ts, "error": ""}

		_:
			return _fail("unknown msgid: %d" % frame.msgid)



# ─── helper ─────────────────────────────────────────────────

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msgid": -1, "data": {}, "error": msg}
