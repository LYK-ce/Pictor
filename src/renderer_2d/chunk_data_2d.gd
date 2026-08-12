class_name ChunkData2D
extends Resource
## Presented by KeJi
## Date ： 2026-08-11
##
## ChunkData2D — 256×256 网格的 PackedByteArray 存储
## Task 21：存储语义 = log-odds i8 的位模式（−8~+8，u8 存储 / i8 解释）
##   - cells[i] 数值 0~127 为正（含 0），>127 需减 256 得负（如 0xF8=248 → −8）
##   - 三态不再存储，显示层按阈值 ±6 派生


@export var cells: PackedByteArray


# ─── 有符号转换辅助（u8 存储 ↔ i8 解释，供协议层/数据层/渲染层共用）──

static func to_i8(b: int) -> int:
	## u8 → i8：PackedByteArray 读出为 0~255，负值位模式需还原（248 → −8）
	return b if b <= 127 else b - 256


static func to_u8(v: int) -> int:
	## i8 → u8 位模式（−8 → 0xF8，−1 → 0xFF），用于写入 PackedByteArray
	return v & 0xFF


static func to_state(log: int) -> int:
	## log-odds → 三态派生（阈值严格：>+6 Occupied / <−6 Free / 其余 Unknown）
	if log > ProtocolDef.LOG_ODDS_THRESHOLD:
		return ProtocolDef.CELL_OCCUPIED
	if log < -ProtocolDef.LOG_ODDS_THRESHOLD:
		return ProtocolDef.CELL_FREE
	return ProtocolDef.CELL_UNKNOWN
