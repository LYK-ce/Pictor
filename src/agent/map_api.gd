## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## MapApi — 通行校验层（task_51 Step 2 §3.3）：agent 的「这点能不能站」工具
## 纯静态（同 VehicleApi / TargetAlloc / MapAccumulator 的风格）：无节点、无 Autoload、不 import 场景，
## headless 下可 `-s` 直测。唯一入参是 `map_data`（有 `get_cell` / `get_chunk_cells` 的对象，
## 生产环境就是 MapData2D，单测可传 null 或空实例）。
##
## ⚠️ 单格语义，**不做寻路**：只回答「这个点能不能站、不能站的话旁边哪里能站」，
##   不回答「A 能不能走到 B」（那要全图搜索，本层一行都没有；Pictor 至今没有寻路）。
##
## ⚠️ 三条语义边界（必读）：
##   ① 全车共用一张图：MapData2D.set_full 是 replace 语义、map_delta_received 不带 vehicle_id
##      （map_data_2d.gd:24 / :41），所以本层校验的是「终端手里这一份合并图」，不是某台车自己的图；
##      多车地图一致性在车端，不在这里。
##   ② 地图未到 ≠ 未知区域：没有 chunk 时 get_cell 返回 0 → 派生 Unknown，
##      光看 state 分不出「还没收到地图」和「收到了但这里是未知」，靠返回里的 has_map 区分。
##   ③ 未知按可通行是乐观的：车端 D* 的判据是「在界内 && 本格 != Occupied && 不在动态障碍」
##      （pleiades-ugv/src/ugv/nav/pathfinder.rs:276-281），Unknown 也算可通行；本层同口径，
##      故 passable=true **不等于**「走得到」，更不等于「路上没障碍」——后者本步不做。
##
## 换算与三态派生全部复用现成件，本文件不写换算公式、不写阈值：
##   米 → 格：CoordUtils.game_to_tile(CoordUtils.real_to_game(x, y))
##   格 → 米（格中心）：CoordUtils.tile_to_real(gx, gy)
##   三态：ChunkData2D.to_state(map_data.get_cell(gx, gy))

class_name MapApi
extends RefCounted

## 世界边长（米）：与 pleiades-ugv / -uav / -sim 的 WORLD_MIN/WORLD_MAX（0 / 128）同口径，
## 世界是左闭右开区间 [0, WORLD_SIZE_M)（= MAP_WIDTH 格 × MAP_RESOLUTION 米/格）。
## 这个值由单测与 ProtocolDef.MAP_WIDTH * ProtocolDef.MAP_RESOLUTION 对齐，不各自漂。
const WORLD_SIZE_M := 128.0

## Pictor 的 2D 地图是**单块** chunk（世界正好 MAP_WIDTH × MAP_HEIGHT 格），
## 所以「有没有地图」只看第 (0,0) 块（同 MapAccumulator 的单 chunk 假设）。
const MAP_CHUNK := Vector2i(0, 0)

## 最近可行点搜索的默认半径（格）：20 格 = 20 × MAP_RESOLUTION = 10 m。
const DEFAULT_MAX_RADIUS_CELLS := 20

## reason 取值：free / unknown 的区别就是「确认过的空地」与「还没建图」
const REASON_FREE := "free"
const REASON_UNKNOWN := "unknown"
const REASON_OCCUPIED := "occupied"
const REASON_OUT_OF_BOUNDS := "out_of_bounds"
const REASON_NO_MAP := "no_map"

## nearest.kind 取值（两段式：先 free，退回 unknown 时必须标出来）
const KIND_FREE := "free"
const KIND_UNKNOWN := "unknown"

## opt 支持的键（可缺省；未知键忽略——模型可能多给字段，不该整条失败）
const OPT_MAX_RADIUS_CELLS := "max_radius_cells"


## 通行校验：世界坐标（米）→ 该格三态 / 是否可通行 / 必要时给最近可行点。
## 返回 11 键（任务文档 §3.3-3）：ok / reason / x / y / gx / gy / state / passable / has_map /
## nearest / cells_checked。opt 支持 max_radius_cells（int，缺省 DEFAULT_MAX_RADIUS_CELLS，0 = 不搜）。
static func Check(map_data, x: float, y: float, opt: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"reason": REASON_OUT_OF_BOUNDS,
		"x": x,
		"y": y,
		"gx": 0,
		"gy": 0,
		"state": ProtocolDef.CELL_UNKNOWN,
		"passable": false,
		"has_map": _has_map(map_data),
		"nearest": null,
		"cells_checked": 0,
	}
	# ① 越界只拒两种：非有限值 / 超出 [0, WORLD_SIZE_M)。
	#    越界时 state 只是哨兵值（UNKNOWN），不据此判可通行——世界外没有「格」，passable 一律 false。
	if not _in_world(x, y):
		return result
	var cell := CoordUtils.game_to_tile(CoordUtils.real_to_game(x, y))
	result["ok"] = true
	result["gx"] = cell.x
	result["gy"] = cell.y
	# ② 没有任何地图数据源：坐标可判，但无格可查；按「未知也可通行」乐观取 true，靠 reason 区分出来
	if not (map_data is Object) or not map_data.has_method("get_cell"):
		result["reason"] = REASON_NO_MAP
		result["passable"] = true
		return result
	# ③ 三态与可通行：Unknown 也可通行（与车端 D* 同口径，见文件头 ③）
	var state := _cell_state(map_data, cell.x, cell.y)
	var passable := state != ProtocolDef.CELL_OCCUPIED
	result["state"] = state
	result["passable"] = passable
	if state == ProtocolDef.CELL_OCCUPIED:
		result["reason"] = REASON_OCCUPIED
	elif state == ProtocolDef.CELL_FREE:
		result["reason"] = REASON_FREE
	else:
		result["reason"] = REASON_UNKNOWN
	# ④ 最近可行点：只在「这点不能站」时才找（能站时这点本身就是落点）
	if not passable:
		var found := _nearest_passable(map_data, x, y, cell, _radius_from(opt))
		result["nearest"] = found["nearest"]
		result["cells_checked"] = found["cells_checked"]
	return result


## 切比雪夫环外扩找最近可行点，两段式：
##   第一段：r = 1..radius 逐环、环内序固定（正北起顺时针），**第一个 CELL_FREE 即返回**；
##   第二段：整段扫完仍无 Free，才退回「第一个非 Occupied」（通常是 Unknown），标 kind="unknown"。
## Free 优先于更近的 Unknown：给 agent 一个未知区落点等于让它赌，但空旷新场地全是 Unknown，
## 只认 Free 又会永远返回「没有落点」；退回时用 kind 把风险标出来，由上层决定收不收。
## 返回 { nearest: Dictionary|null, cells_checked: int }；cells_checked 只统计在世界内真正查过的格。
static func _nearest_passable(map_data, px: float, py: float, cell: Vector2i, radius: int) -> Dictionary:
	var checked := 0
	var fallback: Variant = null
	for r in range(1, radius + 1):
		for offset: Vector2i in _ring(cell, r):
			if not _in_cell_world(offset.x, offset.y):
				continue
			checked += 1
			var state := _cell_state(map_data, offset.x, offset.y)
			if state == ProtocolDef.CELL_FREE:
				return {
					"nearest": _nearest_record(offset.x, offset.y, KIND_FREE, px, py),
					"cells_checked": checked,
				}
			if fallback == null and state != ProtocolDef.CELL_OCCUPIED:
				fallback = offset
	var near: Variant = null
	if fallback != null:
		near = _nearest_record(fallback.x, fallback.y, KIND_UNKNOWN, px, py)
	return {"nearest": near, "cells_checked": checked}


## 半径 r 的一环，共 8r 格，顺序固定：正北 → 顺时针（东 → 南 → 西 → 回到正北之前）。
## 环内序固定是为了让「同样近」的多个落点每次选同一个（可复现、不随机）。
static func _ring(cell: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append(Vector2i(cell.x, cell.y - r))                  # ① 正北
	for i in range(1, r + 1):
		out.append(Vector2i(cell.x + i, cell.y - r))         # ② 北边东行（含东北角）
	for j in range(-r + 1, r + 1):
		out.append(Vector2i(cell.x + r, cell.y + j))         # ③ 东边南行（含东南角）
	for i in range(r - 1, -r - 1, -1):
		out.append(Vector2i(cell.x + i, cell.y + r))         # ④ 南边西行（含西南角）
	for j in range(r - 1, -r - 1, -1):
		out.append(Vector2i(cell.x - r, cell.y + j))         # ⑤ 西边北行（含西北角）
	for i in range(-r + 1, 0):
		out.append(Vector2i(cell.x + i, cell.y - r))         # ⑥ 北边东行，回到正北之前
	return out


## 落点记录：x/y 取**格中心**（与 Step 1 的 sub_target 同口径），dist_m 是入参点到该格中心的欧氏距离
static func _nearest_record(gx: int, gy: int, kind: String, px: float, py: float) -> Dictionary:
	var center := CoordUtils.tile_to_real(gx, gy)
	return {
		"x": center.x,
		"y": center.y,
		"gx": gx,
		"gy": gy,
		"dist_m": center.distance_to(Vector2(px, py)),
		"kind": kind,
	}


static func _cell_state(map_data, gx: int, gy: int) -> int:
	return ChunkData2D.to_state(int(map_data.get_cell(gx, gy)))


## 有没有地图：只看第 (0,0) 块（世界正好一块）。纯诊断量，与坐标是否越界无关。
static func _has_map(map_data) -> bool:
	if not (map_data is Object) or not map_data.has_method("get_chunk_cells"):
		return false
	var cells: PackedByteArray = map_data.get_chunk_cells(MAP_CHUNK.x, MAP_CHUNK.y)
	return not cells.is_empty()


static func _in_world(x: float, y: float) -> bool:
	if not is_finite(x) or not is_finite(y):
		return false
	return x >= 0.0 and y >= 0.0 and x < WORLD_SIZE_M and y < WORLD_SIZE_M


static func _in_cell_world(gx: int, gy: int) -> bool:
	return gx >= 0 and gy >= 0 and gx < ProtocolDef.MAP_WIDTH and gy < ProtocolDef.MAP_HEIGHT


## opt.max_radius_cells → R：缺省 20；非数字回退缺省；clamp 到 [0, MAP_WIDTH]（防模型给天文数字半径卡死界面）
static func _radius_from(opt: Dictionary) -> int:
	var raw: Variant = opt.get(OPT_MAX_RADIUS_CELLS, DEFAULT_MAX_RADIUS_CELLS)
	if not (raw is int or raw is float):
		return DEFAULT_MAX_RADIUS_CELLS
	if not is_finite(float(raw)):
		return DEFAULT_MAX_RADIUS_CELLS
	return clampi(int(raw), 0, ProtocolDef.MAP_WIDTH)
