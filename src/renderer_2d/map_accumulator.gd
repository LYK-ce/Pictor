class_name MapAccumulator
extends RefCounted
## Presented by KeJi
## Date ： 2026-08-12
##
## MapAccumulator — 地图合并纯静态助手（无 EventBus/Node 依赖，可 -s 单测）
## 阶段 2 多车聚合：整表累加 / Δ 应用，全部"先加后 clamp ±8"（与车端语义一致）
## 单 chunk(0,0) 假设：全图 256×256，gx/gy ∈ [0, 256)


const CLAMP := ProtocolDef.LOG_ODDS_CLAMP            # 8
const W := ProtocolDef.MAP_WIDTH                     # 256
const H := ProtocolDef.MAP_HEIGHT                    # 256


## 整表逐格累加（i8 域相加后 clamp ±8），返回新表，不修改入参
static func add_full(dst: PackedByteArray, src: PackedByteArray) -> PackedByteArray:
	var out := dst.duplicate()
	var n := mini(dst.size(), src.size())
	for i in range(n):
		var v := ChunkData2D.to_i8(dst[i]) + ChunkData2D.to_i8(src[i])
		out[i] = ChunkData2D.to_u8(clampi(v, -CLAMP, CLAMP))
	return out


## 将全局 gx/gy 的 Δ 列表应用到 flat 表（先加后 clamp），返回新表，不修改入参
## 越界坐标（gx/gy ∉ [0, 256)）忽略
static func apply_delta_bytes(dst: PackedByteArray, voxels: Array) -> PackedByteArray:
	var out := dst.duplicate()
	for v in voxels:
		var gx: int = v.get("gx", 0)
		var gy: int = v.get("gy", 0)
		if gx < 0 or gy < 0 or gx >= W or gy >= H:
			continue
		var idx := gy * W + gx
		if idx >= 0 and idx < out.size():
			var old := ChunkData2D.to_i8(out[idx])
			out[idx] = ChunkData2D.to_u8(clampi(old + v.get("delta", 0), -CLAMP, CLAMP))
	return out
