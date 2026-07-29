## Presented by KeJi
## Date: 2026-07-29
##
## MessageParser — 上行消息解析器（小车 → PC）
## 纯静态方法，无状态。将原始 JSON / 二进制帧解析为结构化结果。

class_name MessageParser
extends RefCounted


# ─── JSON 文本消息 ──────────────────────────────────────────

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


# ─── 二进制帧 ──────────────────────────────────────────────

## 解析二进制帧。
## 返回: { ok: bool, type: int, chunk_x: int, chunk_y: int, cells: PackedByteArray, error: String }
static func parse_binary(pkt: PackedByteArray) -> Dictionary:
	var size := pkt.size()
	if size < ProtocolDef.BIN_CELLS_OFFSET + 1:
		return _fail("binary frame too small: %d bytes" % size)

	var bin_type: int = pkt[ProtocolDef.BIN_TYPE_OFFSET]
	match bin_type:
		ProtocolDef.BIN_MAP_FULL_TYPE:
			if size < ProtocolDef.BIN_FRAME_SIZE:
				return _fail("map_full frame truncated: %d bytes" % size)
			var chunk_x := pkt.decode_s32(ProtocolDef.BIN_CHUNK_X_OFFSET)
			var chunk_y := pkt.decode_s32(ProtocolDef.BIN_CHUNK_Y_OFFSET)
			var cells := pkt.slice(ProtocolDef.BIN_CELLS_OFFSET)
			return {
				"ok": true,
				"type": bin_type,
				"chunk_x": chunk_x,
				"chunk_y": chunk_y,
				"cells": cells,
				"error": "",
			}
		_:
			return _fail("unknown binary type: %d" % bin_type)


# ─── helper ────────────────────────────────────────────────

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "type": "", "data": {}, "error": msg}
