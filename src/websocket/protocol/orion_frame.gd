## Presented by KeJi
## Date ： 2026-08-07
##
## OrionFrame — Orion 统一协议帧编解码（MAVLink 风格 + 按需扩展）
## 规范文档：docs/orion_protocol.md
##
## 帧布局（全部大端）：
##   magic(1B=0x4F) + len(u32) + seq(u8) + sysid(u8) + compid(u8)
##   + msgid(u16) + payload(N) + checksum(u16)
## 第一版：seq / checksum 恒填 0（libp2p/TCP 已保证可靠与完整）
## 总开销 12 字节，payload 偏移 10。
##
## ⚠️ 字节序：协议规定全大端。Godot 原生 PackedByteArray.encode_u32/decode_u32
##    等均为小端，必须使用本类提供的大端 helper（Read_*/Write_*）。

class_name OrionFrame
extends RefCounted

const MAGIC := 0x4F

const LEN_OFFSET := 1
const SEQ_OFFSET := 5
const SYSID_OFFSET := 6
const COMPID_OFFSET := 7
const MSGID_OFFSET := 8
const PAYLOAD_OFFSET := 10
const HEADER_SIZE := 12      # 1 + 4 + 1 + 1 + 1 + 2 + 2
const CHECKSUM_SIZE := 2


# ─── 大端编解码 helper（协议要求 BE，Godot 原生 API 为 LE）────────

static func Write_U16_BE(buf: PackedByteArray, offset: int, value: int) -> void:
	buf[offset] = (value >> 8) & 0xFF
	buf[offset + 1] = value & 0xFF


static func Read_U16_BE(buf: PackedByteArray, offset: int) -> int:
	return (buf[offset] << 8) | buf[offset + 1]


static func Write_S16_BE(buf: PackedByteArray, offset: int, value: int) -> void:
	Write_U16_BE(buf, offset, value & 0xFFFF)


static func Read_S16_BE(buf: PackedByteArray, offset: int) -> int:
	var v := Read_U16_BE(buf, offset)
	if v & 0x8000:
		v -= 0x10000
	return v


static func Write_U32_BE(buf: PackedByteArray, offset: int, value: int) -> void:
	buf[offset] = (value >> 24) & 0xFF
	buf[offset + 1] = (value >> 16) & 0xFF
	buf[offset + 2] = (value >> 8) & 0xFF
	buf[offset + 3] = value & 0xFF


static func Read_U32_BE(buf: PackedByteArray, offset: int) -> int:
	return (buf[offset] << 24) | (buf[offset + 1] << 16) | (buf[offset + 2] << 8) | buf[offset + 3]


static func Write_S32_BE(buf: PackedByteArray, offset: int, value: int) -> void:
	Write_U32_BE(buf, offset, value & 0xFFFFFFFF)


static func Read_S32_BE(buf: PackedByteArray, offset: int) -> int:
	var v := Read_U32_BE(buf, offset)
	if v & 0x80000000:
		v -= 0x100000000
	return v


static func Write_F32_BE(buf: PackedByteArray, offset: int, value: float) -> void:
	buf.encode_float(offset, value)  # Godot 原生小端写入
	# 反转 4 字节 → 大端
	var t := buf[offset]
	buf[offset] = buf[offset + 3]
	buf[offset + 3] = t
	t = buf[offset + 1]
	buf[offset + 1] = buf[offset + 2]
	buf[offset + 2] = t


static func Read_F32_BE(buf: PackedByteArray, offset: int) -> float:
	# 拷贝 4 字节并反转 → 小端读取
	var tmp := PackedByteArray([buf[offset + 3], buf[offset + 2], buf[offset + 1], buf[offset]])
	return tmp.decode_float(0)


# ─── 帧编解码 ───────────────────────────────────────────────

## 编码一条完整帧（seq / checksum 恒 0）。
static func Encode_Frame(msgid: int, sysid: int, compid: int, payload: PackedByteArray) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(HEADER_SIZE + payload.size())
	buf[0] = MAGIC
	Write_U32_BE(buf, LEN_OFFSET, payload.size())
	buf[SEQ_OFFSET] = 0
	buf[SYSID_OFFSET] = sysid
	buf[COMPID_OFFSET] = compid
	Write_U16_BE(buf, MSGID_OFFSET, msgid)
	for i in range(payload.size()):
		buf[PAYLOAD_OFFSET + i] = payload[i]
	# checksum 恒 0（buf 已初始化为 0）
	return buf


## 解码一条完整帧。
## 返回: { ok: bool, msgid: int, sysid: int, compid: int, payload: PackedByteArray, error: String }
static func Decode_Frame(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < HEADER_SIZE:
		return _Fail("frame too small: %d bytes" % pkt.size())
	if pkt[0] != MAGIC:
		return _Fail("bad magic 0x%02X" % pkt[0])
	var payload_len := Read_U32_BE(pkt, LEN_OFFSET)
	if payload_len != pkt.size() - HEADER_SIZE:
		return _Fail("len mismatch: header=%d actual=%d" % [payload_len, pkt.size() - HEADER_SIZE])
	return {
		"ok": true,
		"msgid": Read_U16_BE(pkt, MSGID_OFFSET),
		"sysid": pkt[SYSID_OFFSET],
		"compid": pkt[COMPID_OFFSET],
		"payload": pkt.slice(PAYLOAD_OFFSET, pkt.size() - CHECKSUM_SIZE),
		"error": "",
	}


static func _Fail(msg: String) -> Dictionary:
	return {"ok": false, "msgid": -1, "sysid": 0, "compid": 0, "payload": PackedByteArray(), "error": msg}
