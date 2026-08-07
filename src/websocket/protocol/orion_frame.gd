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


## 编码一条完整帧（seq / checksum 恒 0）。
static func Encode_Frame(msgid: int, sysid: int, compid: int, payload: PackedByteArray) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(HEADER_SIZE + payload.size())
	buf[0] = MAGIC
	buf.encode_u32(LEN_OFFSET, payload.size())
	buf[SEQ_OFFSET] = 0
	buf[SYSID_OFFSET] = sysid
	buf[COMPID_OFFSET] = compid
	buf.encode_u16(MSGID_OFFSET, msgid)
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
	var payload_len := pkt.decode_u32(LEN_OFFSET)
	if payload_len != pkt.size() - HEADER_SIZE:
		return _Fail("len mismatch: header=%d actual=%d" % [payload_len, pkt.size() - HEADER_SIZE])
	return {
		"ok": true,
		"msgid": pkt.decode_u16(MSGID_OFFSET),
		"sysid": pkt[SYSID_OFFSET],
		"compid": pkt[COMPID_OFFSET],
		"payload": pkt.slice(PAYLOAD_OFFSET, pkt.size() - CHECKSUM_SIZE),
		"error": "",
	}


static func _Fail(msg: String) -> Dictionary:
	return {"ok": false, "msgid": -1, "sysid": 0, "compid": 0, "payload": PackedByteArray(), "error": msg}
