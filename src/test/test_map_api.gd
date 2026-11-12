extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## MapApi 单测（task_51 Step 2 §3.3-8 / §3.4）
## 用法: godot --headless --path <项目> -s res://src/test/test_map_api.gd
## 覆盖 11 组（文档 §3.3-8 的 7 条 + 4 条附加）：
##   ① no_data_source     无数据源（map_data=null）
##   ② no_chunk_yet       有实例、一块 chunk 都没到
##   ③ free_cell          目标格 Free（reason 的 "free" 分支）          〔附加〕
##   ④ occupied_cell      目标格 Occupied                              §3.3-8-2
##   ⑤ unknown_fallback   两段式退回 Unknown + 缺省 R=20 的 cells_checked 〔附加〕
##   ⑥ nearest_free_ring1 环 1 命中 Free，dist_m=0.5、x/y=格中心         §3.3-8-3
##   ⑦ ring_order         3×3 占用 → 环 2 正北先命中（环内序固定）        §3.3-8-4
##   ⑧ no_nearest         全占用：R=2 → null、R=0 → 不搜                 §3.3-8-5
##   ⑨ out_of_bounds      6 例越界（200/128.0/−0.1/NaN/Inf…）            §3.3-8-6
##   ⑩ conversion         换算一致性（128 / 64.25 / 边界 255）           §3.3-8-7
##   ⑪ result_shape       11 键 + nearest 6 键 + opt 容错                〔附加〕
##
## 用**运行期 `load()`** 取 MapData2D 脚本（不是 `preload`）：`map_data_2d.gd` 的 `_ready` 里直写
## autoload 标识符 `EventBus`，`preload` 会在 `-s` 脚本编译期把它当依赖一起编译 → `Identifier not found`。
## `new()` 后**不进树** ⇒ `_ready` 不跑、不连 EventBus 信号；`set_full` 是普通方法，可直接调
## （与 src/test/test_vehicle_api.gd 同做法）。MapApi 纯静态、不碰 EventBus，用 `preload` 即可。
##
## 变量一律**不声明静态类型**（`var map = ...`，不是 `var map: Node`）：在 `Node` 上取脚本成员会解析失败
## （教训见 Workbook/wb_41_containment.md 偏差 #2）。PackedByteArray 也不跨函数就地改入参
## （COW/引用语义不必赌），每张图都在本函数作用域里建完再 upload。

const MAP_SCRIPT := "res://src/renderer_2d/map_data_2d.gd"
const Api := preload("res://src/agent/map_api.gd")

## 目标格：世界点 (64.0, 64.0) 落在格 128 的**左下角**，格中心是 (64.25, 64.25)
const CELL_GX := 128
const CELL_GY := 128
const CELL_X := 64.25
const CELL_Y := 64.25

## set_full 的入参（车标识对 MapData2D 无意义，只出现在它自己的 DEBUG 打印里）
const VEHICLE := "test"
const CHUNK_X := 0
const CHUNK_Y := 0

## Check 返回的 11 键（一个不多一个不少）
const RESULT_KEYS := [
	"ok", "reason", "x", "y", "gx", "gy", "state", "passable", "has_map", "nearest", "cells_checked",
]
## nearest 的 6 键
const NEAREST_KEYS := ["x", "y", "gx", "gy", "dist_m", "kind"]

var _map_script: Script = null


func _initialize() -> void:
	_map_script = load(MAP_SCRIPT) as Script
	if _map_script == null:
		print("FAIL load ", MAP_SCRIPT)
		print("=== ALL PASS: false ===")
		quit(1)
		return
	var ok := true
	ok = ok and _test_no_data_source()
	ok = ok and _test_no_chunk_yet()
	ok = ok and _test_free_cell()
	ok = ok and _test_occupied_cell()
	ok = ok and _test_unknown_fallback()
	ok = ok and _test_nearest_free_ring1()
	ok = ok and _test_ring_order()
	ok = ok and _test_no_nearest()
	ok = ok and _test_out_of_bounds()
	ok = ok and _test_conversion()
	ok = ok and _test_result_shape_and_opt()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


# ─── 工具 ──────────────────────────────────────────────────────

func _expect(cond: bool, tag: String, msg: String) -> bool:
	if cond:
		return true
	print("FAIL ", tag, ": ", msg)
	return false


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0e-6


## 新建 MapData2D 实例（**不进树**：_ready 不跑，不连 EventBus 信号）
func _new_map():
	return _map_script.new()


## 空白 chunk：全 0 = log-odds 0 = Unknown（尺寸取协议常量，不写字面量）
func _blank_cells() -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(ProtocolDef.CHUNK_SIZE * ProtocolDef.CHUNK_SIZE)
	return cells


func _idx(gx: int, gy: int) -> int:
	return gy * ProtocolDef.CHUNK_SIZE + gx


## 走生产路径上传：set_full（clamp + EventBus.chunk_updated.emit）
func _upload(cells: PackedByteArray):
	var map = _new_map()
	map.set_full(VEHICLE, CHUNK_X, CHUNK_Y, cells)
	return map


## 目标格 Occupied，其余全 Unknown
func _upload_occupied_only():
	var cells := _blank_cells()
	cells[_idx(CELL_GX, CELL_GY)] = ChunkData2D.to_u8(ProtocolDef.LOG_ODDS_CLAMP)
	return _upload(cells)


## 目标格 Free
func _upload_free_only():
	var cells := _blank_cells()
	cells[_idx(CELL_GX, CELL_GY)] = ChunkData2D.to_u8(-ProtocolDef.LOG_ODDS_CLAMP)
	return _upload(cells)


## 目标格 Occupied + 正北邻居 Free（环 1 第一格就是 Free）
func _upload_free_north():
	var cells := _blank_cells()
	cells[_idx(CELL_GX, CELL_GY)] = ChunkData2D.to_u8(ProtocolDef.LOG_ODDS_CLAMP)
	cells[_idx(CELL_GX, CELL_GY - 1)] = ChunkData2D.to_u8(-ProtocolDef.LOG_ODDS_CLAMP)
	return _upload(cells)


## 3×3 全 Occupied + 环 2 全 Free（用来看「环 1 扫完 8 格、环 2 第一格就命中」）
func _upload_block_3x3():
	var cells := _blank_cells()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			cells[_idx(CELL_GX + dx, CELL_GY + dy)] = ChunkData2D.to_u8(ProtocolDef.LOG_ODDS_CLAMP)
	for c: Vector2i in _ring_cells(2):
		cells[_idx(c.x, c.y)] = ChunkData2D.to_u8(-ProtocolDef.LOG_ODDS_CLAMP)
	return _upload(cells)


## 全图 Occupied
func _upload_all_occupied():
	var cells := _blank_cells()
	cells.fill(ChunkData2D.to_u8(ProtocolDef.LOG_ODDS_CLAMP))
	return _upload(cells)


## 以目标格为心、切比雪夫半径 r 的 8r 格（测试里独立算，**不复用** MapApi._ring，避免自证）
func _ring_cells(r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) != r:
				continue
			out.append(Vector2i(CELL_GX + dx, CELL_GY + dy))
	return out


# ─── ① 无数据源 ────────────────────────────────────────────────

func _test_no_data_source() -> bool:
	var tag := "no_data_source"
	var r := Api.Check(null, 64.0, 64.0)
	var ok := true
	ok = ok and _expect(bool(r["ok"]), tag, "ok 非 true（坐标本身判得了）")
	ok = ok and _expect(str(r["reason"]) == Api.REASON_NO_MAP, tag, "reason=%s" % str(r["reason"]))
	ok = ok and _expect(not bool(r["has_map"]), tag, "has_map 非 false")
	ok = ok and _expect(int(r["state"]) == ProtocolDef.CELL_UNKNOWN, tag, "state=%d" % int(r["state"]))
	ok = ok and _expect(bool(r["passable"]), tag, "passable 非 true（未知也通行）")
	ok = ok and _expect(r["nearest"] == null, tag, "nearest 非 null: %s" % str(r["nearest"]))
	ok = ok and _expect(int(r["cells_checked"]) == 0, tag, "cells_checked=%d" % int(r["cells_checked"]))
	ok = ok and _expect(int(r["gx"]) == CELL_GX and int(r["gy"]) == CELL_GY, tag,
			"gx/gy=%d/%d" % [int(r["gx"]), int(r["gy"])])
	if ok:
		print("PASS ", tag)
	return ok


# ─── ② 有实例、一块 chunk 都没到 ──────────────────────────────

func _test_no_chunk_yet() -> bool:
	var tag := "no_chunk_yet"
	var map = _new_map()
	var r := Api.Check(map, 64.0, 64.0)
	var ok := true
	ok = ok and _expect(bool(r["ok"]), tag, "ok 非 true")
	ok = ok and _expect(str(r["reason"]) == Api.REASON_UNKNOWN, tag, "reason=%s" % str(r["reason"]))
	ok = ok and _expect(not bool(r["has_map"]), tag, "has_map 非 false（一块 chunk 都没收到）")
	ok = ok and _expect(int(r["state"]) == ProtocolDef.CELL_UNKNOWN, tag, "state=%d" % int(r["state"]))
	ok = ok and _expect(bool(r["passable"]), tag, "passable 非 true")
	ok = ok and _expect(r["nearest"] == null, tag, "passable=true 时不该搜最近点，nearest=%s" % str(r["nearest"]))
	ok = ok and _expect(int(r["cells_checked"]) == 0, tag, "cells_checked=%d" % int(r["cells_checked"]))
	ok = ok and _expect(int(r["gx"]) == CELL_GX and int(r["gy"]) == CELL_GY, tag,
			"gx/gy=%d/%d" % [int(r["gx"]), int(r["gy"])])
	# 换个 R 也一样：可通行就不搜
	var r2 := Api.Check(map, 64.0, 64.0, {"max_radius_cells": 5})
	ok = ok and _expect(r2["nearest"] == null and int(r2["cells_checked"]) == 0, tag,
			"R=5 仍不该搜（nearest=%s checked=%d）" % [str(r2["nearest"]), int(r2["cells_checked"])])
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ③ 目标格 Free（reason 的 free 分支）────────────────────────

func _test_free_cell() -> bool:
	var tag := "free_cell"
	var map = _upload_free_only()
	var r := Api.Check(map, CELL_X, CELL_Y)
	var ok := true
	ok = ok and _expect(bool(r["has_map"]), tag, "has_map 非 true（set_full 之后应已建图）")
	ok = ok and _expect(int(r["state"]) == ProtocolDef.CELL_FREE, tag, "state=%d 非 FREE" % int(r["state"]))
	ok = ok and _expect(str(r["reason"]) == Api.REASON_FREE, tag, "reason=%s 非 free" % str(r["reason"]))
	ok = ok and _expect(bool(r["passable"]), tag, "passable 非 true")
	ok = ok and _expect(r["nearest"] == null, tag, "能站时 nearest 应为 null: %s" % str(r["nearest"]))
	ok = ok and _expect(int(r["cells_checked"]) == 0, tag, "cells_checked=%d" % int(r["cells_checked"]))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ④ 目标格 Occupied（§3.3-8-2）──────────────────────────────

func _test_occupied_cell() -> bool:
	var tag := "occupied_cell"
	var map = _upload_occupied_only()
	var r := Api.Check(map, CELL_X, CELL_Y)
	var ok := true
	ok = ok and _expect(bool(r["ok"]), tag, "ok 非 true")
	ok = ok and _expect(bool(r["has_map"]), tag, "has_map 非 true")
	ok = ok and _expect(int(r["state"]) == ProtocolDef.CELL_OCCUPIED, tag, "state=%d 非 OCCUPIED" % int(r["state"]))
	ok = ok and _expect(not bool(r["passable"]), tag, "passable 非 false")
	ok = ok and _expect(str(r["reason"]) == Api.REASON_OCCUPIED, tag, "reason=%s" % str(r["reason"]))
	ok = ok and _expect(int(r["gx"]) == CELL_GX and int(r["gy"]) == CELL_GY, tag,
			"gx/gy=%d/%d" % [int(r["gx"]), int(r["gy"])])
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑤ 两段式退回 Unknown（R 内无 Free）────────────────────────

func _test_unknown_fallback() -> bool:
	var tag := "unknown_fallback"
	var map = _upload_occupied_only()
	var r := Api.Check(map, CELL_X, CELL_Y)
	var ok := true
	ok = ok and _expect(r["nearest"] is Dictionary, tag, "nearest 非 Dictionary: %s" % str(r["nearest"]))
	if ok:
		var n: Dictionary = r["nearest"]
		ok = ok and _expect(str(n["kind"]) == Api.KIND_UNKNOWN, tag,
				"kind=%s（R 内无 Free，应退回 unknown）" % str(n["kind"]))
		ok = ok and _expect(int(n["gx"]) == CELL_GX and int(n["gy"]) == CELL_GY - 1, tag,
				"nearest gx/gy=%d/%d（环 1 第一格 = 正北）" % [int(n["gx"]), int(n["gy"])])
		ok = ok and _expect(_near(float(n["dist_m"]), 0.5), tag, "dist_m=%.6f（期望 0.5）" % float(n["dist_m"]))
		ok = ok and _expect(_near(float(n["x"]), CELL_X) and _near(float(n["y"]), CELL_Y - 0.5), tag,
				"nearest x/y=%.4f/%.4f（格中心）" % [float(n["x"]), float(n["y"])])
	# 缺省 R=20、全程无 Free ⇒ 8×(1+…+20) = 1680 格全部查过
	ok = ok and _expect(int(r["cells_checked"]) == 1680, tag,
			"cells_checked=%d（缺省 R=20，8×(1+…+20)=1680）" % int(r["cells_checked"]))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑥ 环 1 命中 Free（§3.3-8-3）───────────────────────────────

func _test_nearest_free_ring1() -> bool:
	var tag := "nearest_free_ring1"
	var map = _upload_free_north()
	var r := Api.Check(map, CELL_X, CELL_Y)
	var ok := true
	ok = ok and _expect(r["nearest"] is Dictionary, tag, "nearest 非 Dictionary: %s" % str(r["nearest"]))
	if ok:
		var n: Dictionary = r["nearest"]
		ok = ok and _expect(str(n["kind"]) == Api.KIND_FREE, tag, "kind=%s" % str(n["kind"]))
		ok = ok and _expect(int(n["gx"]) == CELL_GX and int(n["gy"]) == CELL_GY - 1, tag,
				"nearest gx/gy=%d/%d" % [int(n["gx"]), int(n["gy"])])
		ok = ok and _expect(_near(float(n["dist_m"]), 0.5), tag,
				"dist_m=%.6f 期望 0.5（正交邻格，1 格 = MAP_RESOLUTION 米）" % float(n["dist_m"]))
		ok = ok and _expect(_near(float(n["x"]), 64.25) and _near(float(n["y"]), 63.75), tag,
				"nearest x/y=%.4f/%.4f 期望 64.25/63.75（格中心）" % [float(n["x"]), float(n["y"])])
	ok = ok and _expect(int(r["cells_checked"]) == 1, tag,
			"cells_checked=%d 期望 1（环 1 第一格就命中 Free）" % int(r["cells_checked"]))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑦ 环内序固定（§3.3-8-4）──────────────────────────────────

func _test_ring_order() -> bool:
	var tag := "ring_order"
	var map = _upload_block_3x3()
	var r := Api.Check(map, CELL_X, CELL_Y)
	var ok := true
	ok = ok and _expect(r["nearest"] is Dictionary, tag, "nearest 非 Dictionary: %s" % str(r["nearest"]))
	if ok:
		var n: Dictionary = r["nearest"]
		ok = ok and _expect(str(n["kind"]) == Api.KIND_FREE, tag, "kind=%s 非 free" % str(n["kind"]))
		ok = ok and _expect(int(n["gx"]) == CELL_GX and int(n["gy"]) == CELL_GY - 2, tag,
				"nearest gx/gy=%d/%d（3×3 以外、环 2 正北先命中）" % [int(n["gx"]), int(n["gy"])])
		ok = ok and _expect(_near(float(n["dist_m"]), 1.0), tag,
				"dist_m=%.6f 期望 1.0（两格正交）" % float(n["dist_m"]))
	ok = ok and _expect(int(r["cells_checked"]) == 9, tag,
			"cells_checked=%d 期望 9（环 1 八格占用 + 环 2 第一格命中）" % int(r["cells_checked"]))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑧ 全占用：R=2 → null；R=0 → 不搜（§3.3-8-5）───────────────

func _test_no_nearest() -> bool:
	var tag := "no_nearest"
	var map = _upload_all_occupied()
	var r := Api.Check(map, CELL_X, CELL_Y, {"max_radius_cells": 2})
	var ok := true
	ok = ok and _expect(str(r["reason"]) == Api.REASON_OCCUPIED, tag, "reason=%s" % str(r["reason"]))
	ok = ok and _expect(not bool(r["passable"]), tag, "passable 非 false")
	ok = ok and _expect(r["nearest"] == null, tag, "R=2 内全 Occupied，nearest 应 null，实际 %s" % str(r["nearest"]))
	ok = ok and _expect(int(r["cells_checked"]) == 24, tag,
			"R=2 cells_checked=%d 期望 24（8×1 + 8×2）" % int(r["cells_checked"]))
	var r0 := Api.Check(map, CELL_X, CELL_Y, {"max_radius_cells": 0})
	ok = ok and _expect(r0["nearest"] == null and int(r0["cells_checked"]) == 0, tag,
			"R=0 应不搜（nearest=%s checked=%d）" % [str(r0["nearest"]), int(r0["cells_checked"])])
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑨ 越界 6 例（§3.3-8-6）───────────────────────────────────

func _test_out_of_bounds() -> bool:
	var tag := "out_of_bounds"
	var map = _upload_occupied_only()          # 有图 ⇒ 顺便证明 has_map 与越界无关
	var ok := true
	var points := [
		Vector2(200.0, 50.0),                  # 超出世界边长
		Vector2(128.0, 64.0),                  # 恰好等于世界边长：世界是 [0, 128)，拒
		Vector2(-0.1, 64.0),                   # 负值
		Vector2(64.0, 128.0),                  # 上边界
		Vector2(NAN, 64.0),                    # NaN
		Vector2(64.0, INF),                    # Inf
	]
	for p: Vector2 in points:
		var r := Api.Check(map, p.x, p.y)
		ok = ok and _expect(not bool(r["ok"]), tag, "(%s) ok 非 false" % str(p))
		ok = ok and _expect(str(r["reason"]) == Api.REASON_OUT_OF_BOUNDS, tag,
				"(%s) reason=%s" % [str(p), str(r["reason"])])
		ok = ok and _expect(not bool(r["passable"]), tag, "(%s) passable 非 false" % str(p))
		ok = ok and _expect(int(r["gx"]) == 0 and int(r["gy"]) == 0, tag,
				"(%s) gx/gy 应为哨兵 0/0，实际 %d/%d" % [str(p), int(r["gx"]), int(r["gy"])])
		ok = ok and _expect(r["nearest"] == null, tag, "(%s) nearest 非 null" % str(p))
		ok = ok and _expect(int(r["cells_checked"]) == 0, tag, "(%s) cells_checked=%d" % [str(p), int(r["cells_checked"])])
		ok = ok and _expect(int(r["state"]) == ProtocolDef.CELL_UNKNOWN, tag,
				"(%s) state=%d（越界哨兵应为 UNKNOWN）" % [str(p), int(r["state"])])
		ok = ok and _expect(bool(r["has_map"]), tag, "(%s) has_map 非 true（有图就该报 true）" % str(p))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑩ 换算一致性（§3.3-8-7）─────────────────────────────────

func _test_conversion() -> bool:
	var tag := "conversion"
	var ok := true
	# 与 test_vehicle_api 同一条事实：世界点 64.0 落在格 128 的**左下角**，格中心是 64.25
	var c := CoordUtils.tile_to_real(CELL_GX, CELL_GY)
	ok = ok and _expect(c == Vector2(64.25, 64.25), tag, "tile_to_real(128,128)=%s" % str(c))
	# 世界尺寸必须与协议常量一致（MapApi 的常量是字面量，这里把它钉在 MAP_WIDTH×MAP_RESOLUTION 上）
	ok = ok and _expect(is_equal_approx(Api.WORLD_SIZE_M, float(ProtocolDef.MAP_WIDTH) * ProtocolDef.MAP_RESOLUTION), tag,
			"WORLD_SIZE_M=%s 与 MAP_WIDTH×MAP_RESOLUTION=%s 不一致" % [
				str(Api.WORLD_SIZE_M), str(float(ProtocolDef.MAP_WIDTH) * ProtocolDef.MAP_RESOLUTION)])
	var r := Api.Check(null, 64.0, 64.0)
	ok = ok and _expect(int(r["gx"]) == CELL_GX and int(r["gy"]) == CELL_GY, tag,
			"Check(64,64) gx/gy=%d/%d" % [int(r["gx"]), int(r["gy"])])
	var via_utils := CoordUtils.game_to_tile(CoordUtils.real_to_game(64.0, 64.0))
	ok = ok and _expect(int(r["gx"]) == via_utils.x and int(r["gy"]) == via_utils.y, tag,
			"gx 与 CoordUtils 链不一致: %d vs %d" % [int(r["gx"]), via_utils.x])
	# 世界左下角 → 格 0；[0, 128) 的最后一格 → 格 MAP_WIDTH-1
	var r0 := Api.Check(null, 0.0, 0.0)
	ok = ok and _expect(bool(r0["ok"]) and int(r0["gx"]) == 0 and int(r0["gy"]) == 0, tag,
			"Check(0,0) ok=%s gx/gy=%d/%d" % [str(r0["ok"]), int(r0["gx"]), int(r0["gy"])])
	var rb := Api.Check(null, 127.99, 127.99)
	ok = ok and _expect(bool(rb["ok"]), tag, "127.99 应仍算界内")
	ok = ok and _expect(int(rb["gx"]) == ProtocolDef.MAP_WIDTH - 1 and int(rb["gy"]) == ProtocolDef.MAP_HEIGHT - 1, tag,
			"边界 gx/gy=%d/%d 期望 %d/%d" % [
				int(rb["gx"]), int(rb["gy"]), ProtocolDef.MAP_WIDTH - 1, ProtocolDef.MAP_HEIGHT - 1])
	# 64.75 落在下一格（129），不是 128
	var rc := Api.Check(null, 64.75, 64.75)
	ok = ok and _expect(int(rc["gx"]) == CELL_GX + 1 and int(rc["gy"]) == CELL_GY + 1, tag,
			"Check(64.75,64.75) gx/gy=%d/%d 期望 129/129" % [int(rc["gx"]), int(rc["gy"])])
	if ok:
		print("PASS ", tag)
	return ok


# ─── ⑪ 返回结构 11 键 + nearest 6 键 + opt 容错 ────────────────

func _test_result_shape_and_opt() -> bool:
	var tag := "result_shape"
	var map = _upload_occupied_only()
	var r := Api.Check(map, CELL_X, CELL_Y, {"max_radius_cells": 1, "unused_key": true})
	var ok := true
	ok = ok and _expect(r.size() == RESULT_KEYS.size(), tag,
			"返回键数=%d 期望 %d 实际键=%s" % [r.size(), RESULT_KEYS.size(), str(r.keys())])
	for k: String in RESULT_KEYS:
		ok = ok and _expect(r.has(k), tag, "缺键 " + k)
	# R=1：环 1 八格全 Unknown ⇒ 退回 unknown，正好查 8 格
	ok = ok and _expect(int(r["cells_checked"]) == 8, tag, "R=1 cells_checked=%d 期望 8" % int(r["cells_checked"]))
	ok = ok and _expect(r["nearest"] is Dictionary, tag, "R=1 nearest 非 Dictionary")
	if ok:
		var n: Dictionary = r["nearest"]
		ok = ok and _expect(n.size() == NEAREST_KEYS.size(), tag,
				"nearest 键数=%d 期望 %d 实际键=%s" % [n.size(), NEAREST_KEYS.size(), str(n.keys())])
		for k: String in NEAREST_KEYS:
			ok = ok and _expect(n.has(k), tag, "nearest 缺键 " + k)
	# 非法 R（字符串）→ 回退缺省 20 ⇒ 全环无 Free ⇒ 1680
	var r2 := Api.Check(map, CELL_X, CELL_Y, {"max_radius_cells": "big"})
	ok = ok and _expect(int(r2["cells_checked"]) == 1680, tag,
			"非法 R 应回退缺省 20，cells_checked=%d" % int(r2["cells_checked"]))
	map.free()
	if ok:
		print("PASS ", tag)
	return ok
