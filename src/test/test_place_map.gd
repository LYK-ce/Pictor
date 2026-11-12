extends SceneTree

## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## PlaceMap 单测（task_51 Step 4 §5.3-7 / §5.4）
## 用法：godot --headless --path Pictor -s src/test/test_place_map.gd
## 期望：末行 `=== ALL PASS: true ===`，退出码 0
## 复现失败：照抄上面这条命令；日志落 tmp/task51/test_place_map.log
##
## 断言失败一律 print("FAIL Tn ...") 并 return false，最后统一打印 ALL PASS
## 只写 user://test_place_map.json（测试专用），跑完删除；不触碰 user://place_map.json
##
## 用 preload 取脚本是安全的：place_map.gd 只引用全局类 CoordUtils，不引用任何 autoload
## （autoload 在 _init 阶段未注册，preload 带 autoload 标识符的脚本才需要改成运行期 load()）。

const PlaceMapScript := preload("res://src/map/place_map.gd")
const TEST_PATH := "user://test_place_map.json"

## 一条记录的 11 个键（与 place_map.gd `Set` 归一化产物同集合；单测独立写一份，防被改）
const ENTRY_KEYS := [
	"id", "name", "aliases", "layer", "kind",
	"gx", "gy", "x", "y", "radius", "updated_at",
]


func _initialize() -> void:
	_cleanup()
	var ok := true
	ok = ok and _test_coord_contract()
	ok = ok and _test_missing_file()
	ok = ok and _test_meters_only()
	ok = ok and _test_cell_only()
	ok = ok and _test_resolve_three_ways()
	ok = ok and _test_not_found()
	ok = ok and _test_ambiguous()
	ok = ok and _test_set_strict()
	ok = ok and _test_roundtrip()
	ok = ok and _test_delete()
	ok = ok and _test_nearest()
	ok = ok and _test_layer_filter()
	ok = ok and _test_bad_json()
	_cleanup()
	print("=== ALL PASS: ", ok, " ===")
	quit(0 if ok else 1)


# ─── 工具 ─────────────────────────────────────────────────

## 删掉测试文件（含可能的 .tmp），保证 T1「文件不存在」可复现
func _cleanup() -> void:
	for p: String in [TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			var _del_err := DirAccess.remove_absolute(p)


## 干净的实例：删文件 → new → Load（每条用例互不污染）
func _fresh():
	_cleanup()
	var m = PlaceMapScript.new(TEST_PATH)
	var _lr: Dictionary = m.Load()
	return m


func _near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


## 准备阶段写入（setup）：Set 必须成功。用 void 包一层，避免丢弃返回值触发 RETURN_VALUE_DISCARDED；
## 失败时打 FAIL 行（后续断言也会跟着失败，不掩盖）
func _seed(m, src: Dictionary) -> void:
	var r: Dictionary = m.Set(src)
	if not bool(r["ok"]):
		print("FAIL seed: Set 被拒 ", src, " → ", r)


# ─── T0 坐标口径（12 条之外的附加 1 条） ────────────────────

## 格界与 ProtocolDef 对齐；1 格 = 0.5 m；格心 = (g+0.5)*0.5；鼠标选点走 game_to_tile
func _test_coord_contract() -> bool:
	if PlaceMapScript.MAX_CELL != ProtocolDef.MAP_WIDTH or PlaceMapScript.MAX_CELL != ProtocolDef.MAP_HEIGHT:
		print("FAIL T0 coord: MAX_CELL=", PlaceMapScript.MAX_CELL, " 与 ProtocolDef(",
			ProtocolDef.MAP_WIDTH, ",", ProtocolDef.MAP_HEIGHT, ") 不一致")
		return false
	if PlaceMapScript.Cell_From_Meters(64.0, 40.0) != Vector2i(128, 80):
		print("FAIL T0 coord: Cell_From_Meters(64,40)=", PlaceMapScript.Cell_From_Meters(64.0, 40.0), " 期望 (128, 80)")
		return false
	# 0.5 m/格：64.5 → 129（若按已过时的 docs 当成 1 m/格，这里会是 64）
	if PlaceMapScript.Cell_From_Meters(64.5, 40.5) != Vector2i(129, 81):
		print("FAIL T0 coord: Cell_From_Meters(64.5,40.5)=", PlaceMapScript.Cell_From_Meters(64.5, 40.5), " 期望 (129, 81)")
		return false
	if PlaceMapScript.Cell_Center(128, 80) != Vector2(64.25, 40.25):
		print("FAIL T0 coord: Cell_Center(128,80)=", PlaceMapScript.Cell_Center(128, 80), " 期望 (64.25, 40.25)")
		return false
	if PlaceMapScript.Cell_Center(0, 0) != Vector2(0.25, 0.25):
		print("FAIL T0 coord: Cell_Center(0,0)=", PlaceMapScript.Cell_Center(0, 0), " 期望 (0.25, 0.25)")
		return false
	# 鼠标选点：游戏像素 / 16 → tile（1028/16=64.25→64，644/16=40.25→40）
	if PlaceMapScript.Cell_From_Game_Pixel(Vector2(1028.0, 644.0)) != Vector2i(64, 40):
		print("FAIL T0 coord: Cell_From_Game_Pixel(1028,644)=", PlaceMapScript.Cell_From_Game_Pixel(Vector2(1028.0, 644.0)), " 期望 (64, 40)")
		return false
	print("PASS T0 coord_contract")
	return true


# ─── T1 §5.3-7-1 文件不存在 → ok=true / count=0 ─────────────

func _test_missing_file() -> bool:
	_cleanup()
	if FileAccess.file_exists(TEST_PATH):
		print("FAIL T1 missing_file: 清理后文件仍在 ", TEST_PATH)
		return false
	var m = PlaceMapScript.new(TEST_PATH)
	var r: Dictionary = m.Load()
	if not bool(r["ok"]):
		print("FAIL T1 missing_file: ok 非 true ", r)
		return false
	if int(r["count"]) != 0 or int(r["skipped"]) != 0 or str(r["error"]) != "":
		print("FAIL T1 missing_file: count/skipped/error=", r["count"], "/", r["skipped"], "/", r["error"], " 期望 0/0/")
		return false
	if m.Count() != 0:
		print("FAIL T1 missing_file: Count=", m.Count())
		return false
	print("PASS T1 missing_file")
	return true


# ─── T2 §5.3-7-2 只给米 → 格号派生、x/y 改写为格心 ──────────

func _test_meters_only() -> bool:
	var m = _fresh()
	var r: Dictionary = m.Set({"id": "park_south_gate", "name": "公园南门", "x": 64.0, "y": 40.0})
	if not bool(r["ok"]) or str(r["error"]) != "":
		print("FAIL T2 meters_only: Set 被拒 ", r)
		return false
	if not bool(r["saved"]):
		print("FAIL T2 meters_only: saved=false（落盘失败）")
		return false
	var e: Dictionary = r["entry"]
	if int(e["gx"]) != 128 or int(e["gy"]) != 80:
		print("FAIL T2 meters_only: gx/gy=", e["gx"], ",", e["gy"], " 期望 128,80")
		return false
	if not _near(float(e["x"]), 64.25) or not _near(float(e["y"]), 40.25):
		print("FAIL T2 meters_only: x/y 未改写成格心 =", e["x"], ",", e["y"], " 期望 64.25,40.25")
		return false
	if m.Count() != 1:
		print("FAIL T2 meters_only: Count=", m.Count(), " 期望 1")
		return false
	print("PASS T2 meters_only")
	return true


# ─── T3 §5.3-7-3 只给格 → 与 T2 同一组 gx/gy、同一个格心 ────

func _test_cell_only() -> bool:
	var m = _fresh()
	var r: Dictionary = m.Set({"id": "park_south_gate", "name": "公园南门", "gx": 128, "gy": 80})
	if not bool(r["ok"]) or str(r["error"]) != "":
		print("FAIL T3 cell_only: Set 被拒 ", r)
		return false
	var e: Dictionary = r["entry"]
	if int(e["gx"]) != 128 or int(e["gy"]) != 80:
		print("FAIL T3 cell_only: gx/gy=", e["gx"], ",", e["gy"], " 期望 128,80")
		return false
	# 与 T2 刻意对照：只给格也必须落到同一个格心 64.25 / 40.25
	if not _near(float(e["x"]), 64.25) or not _near(float(e["y"]), 40.25):
		print("FAIL T3 cell_only: x/y=", e["x"], ",", e["y"], " 期望 64.25,40.25（与 T2 同结果）")
		return false
	if m.Count() != 1:
		print("FAIL T3 cell_only: Count=", m.Count(), " 期望 1")
		return false
	print("PASS T3 cell_only")
	return true


# ─── T4 §5.3-7-4 名称 / 别名 / 带空白别名 三者命中同一 id ────

func _test_resolve_three_ways() -> bool:
	var m = _fresh()
	_seed(m, {"id": "park_south_gate", "name": "公园南门", "aliases": ["南门", "南门口"], "gx": 128, "gy": 80})
	var by_name: Dictionary = m.Resolve("公园南门")
	var by_alias: Dictionary = m.Resolve("南门")
	var by_alias_pad: Dictionary = m.Resolve(" 南门 ")
	for pair: Array in [["name", by_name], ["alias", by_alias], ["alias_pad", by_alias_pad]]:
		var tag := str(pair[0])
		var r: Dictionary = pair[1]
		if not bool(r["ok"]):
			print("FAIL T4 resolve_three_ways: ", tag, " ok=false ", r)
			return false
		if str(r["id"]) != "park_south_gate":
			print("FAIL T4 resolve_three_ways: ", tag, " id=", r["id"], " 期望 park_south_gate")
			return false
		if int(r["gx"]) != 128 or int(r["gy"]) != 80:
			print("FAIL T4 resolve_three_ways: ", tag, " gx/gy=", r["gx"], ",", r["gy"])
			return false
		if not _near(float(r["x"]), 64.25) or not _near(float(r["y"]), 40.25):
			print("FAIL T4 resolve_three_ways: ", tag, " x/y=", r["x"], ",", r["y"])
			return false
		var amb: Array = r["ambiguous"]
		if not amb.is_empty():
			print("FAIL T4 resolve_three_ways: ", tag, " ambiguous 应为空 ", amb)
			return false
	# matched_alias：名称命中为空串，别名命中回显原始别名（带空白的输入也算同一条别名）
	if str(by_name["matched_alias"]) != "":
		print("FAIL T4 resolve_three_ways: 名称命中 matched_alias=", by_name["matched_alias"], " 期望空串")
		return false
	if str(by_alias["matched_alias"]) != "南门" or str(by_alias_pad["matched_alias"]) != "南门":
		print("FAIL T4 resolve_three_ways: 别名命中 matched_alias=", by_alias["matched_alias"], "/", by_alias_pad["matched_alias"])
		return false
	# id 直命中（大小写不敏感）
	var by_id: Dictionary = m.Resolve("PARK_SOUTH_GATE")
	if not bool(by_id["ok"]) or str(by_id["id"]) != "park_south_gate":
		print("FAIL T4 resolve_three_ways: 大写 id 未命中 ", by_id)
		return false
	print("PASS T4 resolve_three_ways")
	return true


# ─── T5 §5.3-7-5 未命中 → ok=false / not_found ─────────────

func _test_not_found() -> bool:
	var m = _fresh()
	_seed(m, {"id": "park_south_gate", "name": "公园南门", "gx": 128, "gy": 80})
	var r: Dictionary = m.Resolve("不存在")
	if bool(r["ok"]):
		print("FAIL T5 not_found: ok 非 false ", r)
		return false
	if str(r["error"]) != "not_found":
		print("FAIL T5 not_found: error=", r["error"], " 期望 not_found")
		return false
	if str(r["id"]) != "":
		print("FAIL T5 not_found: id=", r["id"], " 期望空串")
		return false
	var empty: Dictionary = m.Resolve("   ")
	if bool(empty["ok"]) or str(empty["error"]) != "not_found":
		print("FAIL T5 not_found: 全空白输入 ", empty)
		return false
	print("PASS T5 not_found")
	return true


# ─── T6 §5.3-7-6 两条同名 → ambiguous.size()==2、取字典序最小 ─

func _test_ambiguous() -> bool:
	var m = _fresh()
	_seed(m, {"id": "bbb", "name": "同名点", "gx": 10, "gy": 10})
	_seed(m, {"id": "aaa", "name": "同名点", "gx": 20, "gy": 20})
	var r: Dictionary = m.Resolve("同名点")
	if not bool(r["ok"]):
		print("FAIL T6 ambiguous: ok=false ", r)
		return false
	var amb: Array = r["ambiguous"]
	if amb.size() != 2:
		print("FAIL T6 ambiguous: ambiguous.size()=", amb.size(), " 期望 2 ", amb)
		return false
	if str(r["id"]) != "aaa":
		print("FAIL T6 ambiguous: 选中 id=", r["id"], " 期望字典序最小 aaa")
		return false
	if str(amb[0]) != "aaa" or str(amb[1]) != "bbb":
		print("FAIL T6 ambiguous: ambiguous 内容=", amb, " 期望 [aaa, bbb]")
		return false
	print("PASS T6 ambiguous")
	return true


# ─── T7 §5.3-7-7 Set 七类校验全拒 + 格界两侧 ────────────────

func _test_set_strict() -> bool:
	var m = _fresh()
	var cases := [
		[{"id": "Park South", "name": "x", "gx": 1, "gy": 1}, "bad_id"],
		[{"id": "ok_layer", "name": "x", "layer": "Place!", "gx": 1, "gy": 1}, "bad_layer"],
		[{"id": "ok_name", "name": "   ", "gx": 1, "gy": 1}, "bad_name"],
		[{"id": "ok_alias", "name": "x", "aliases": ["南门", ""], "gx": 1, "gy": 1}, "bad_alias"],
		[{"id": "ok_radius", "name": "x", "radius": -1.0, "gx": 1, "gy": 1}, "bad_radius"],
		[{"id": "ok_coord", "name": "x"}, "bad_coord"],
		[{"id": "ok_bounds", "name": "x", "gx": 1, "gy": 300}, "out_of_bounds"],
	]
	for c: Array in cases:
		var src: Dictionary = c[0]
		var want := str(c[1])
		var r: Dictionary = m.Set(src)
		if bool(r["ok"]):
			print("FAIL T7 set_strict: ", src, " 被接受，期望拒（", want, "）")
			return false
		if str(r["error"]) != want:
			print("FAIL T7 set_strict: ", src, " error=", r["error"], " 期望 ", want)
			return false
	if m.Count() != 0:
		print("FAIL T7 set_strict: 被拒的写入污染了内存，Count=", m.Count())
		return false
	# 格界另一侧：255 合法、256 越界
	var edge_ok: Dictionary = m.Set({"id": "edge_255", "name": "边界", "gx": 255, "gy": 255})
	if not bool(edge_ok["ok"]):
		print("FAIL T7 set_strict: gx=255/gy=255 应合法 ", edge_ok)
		return false
	var edge_bad: Dictionary = m.Set({"id": "edge_256", "name": "越界", "gx": 256, "gy": 0})
	if bool(edge_bad["ok"]) or str(edge_bad["error"]) != "out_of_bounds":
		print("FAIL T7 set_strict: gx=256 应 out_of_bounds ", edge_bad)
		return false
	# 只给一半格号也必须拒（不能静默补 0）
	var half: Dictionary = m.Set({"id": "half_cell", "name": "半格", "gx": 7})
	if bool(half["ok"]) or str(half["error"]) != "bad_coord":
		print("FAIL T7 set_strict: 只给 gx 应 bad_coord ", half)
		return false
	print("PASS T7 set_strict")
	return true


# ─── T8 §5.3-7-8 持久化往返（新实例 Load 后 11 键一致） ─────

func _test_roundtrip() -> bool:
	var m1 = _fresh()
	var r1: Dictionary = m1.Set({
		"id": "rt_point", "name": "往返点", "aliases": ["往返", "往返点"],
		"layer": "place", "kind": "gate", "gx": 128, "gy": 80, "radius": 1.5,
	})
	if not bool(r1["ok"]) or not bool(r1["saved"]):
		print("FAIL T8 roundtrip: 首次 Set 失败 ", r1)
		return false
	var want: Dictionary = r1["entry"]
	var m2 = PlaceMapScript.new(TEST_PATH)
	var lr: Dictionary = m2.Load()
	if not bool(lr["ok"]) or int(lr["count"]) != 1:
		print("FAIL T8 roundtrip: 新实例 Load=", lr, " 期望 ok=true count=1")
		return false
	var rows: Array = m2.All()
	if rows.size() != 1:
		print("FAIL T8 roundtrip: All().size()=", rows.size(), " 期望 1")
		return false
	var back: Dictionary = rows[0]
	for k: String in ENTRY_KEYS:
		if not back.has(k):
			print("FAIL T8 roundtrip: 读回缺键 ", k, " 实际键=", back.keys())
			return false
	# 逐键比（JSON 里数字回来全是 float，这里显式归一，不靠 Variant 弱比较）
	if str(back["id"]) != str(want["id"]) or str(back["name"]) != str(want["name"]):
		print("FAIL T8 roundtrip: id/name=", back["id"], "/", back["name"])
		return false
	if str(back["layer"]) != "place" or str(back["kind"]) != "gate":
		print("FAIL T8 roundtrip: layer/kind=", back["layer"], "/", back["kind"])
		return false
	if int(back["gx"]) != 128 or int(back["gy"]) != 80:
		print("FAIL T8 roundtrip: gx/gy=", back["gx"], ",", back["gy"])
		return false
	if not _near(float(back["x"]), 64.25) or not _near(float(back["y"]), 40.25):
		print("FAIL T8 roundtrip: x/y=", back["x"], ",", back["y"], " 期望 64.25,40.25")
		return false
	if not _near(float(back["radius"]), 1.5):
		print("FAIL T8 roundtrip: radius=", back["radius"], " 期望 1.5")
		return false
	if int(back["updated_at"]) != int(want["updated_at"]):
		print("FAIL T8 roundtrip: updated_at=", back["updated_at"], " 期望 ", want["updated_at"])
		return false
	var ba: Array = back["aliases"]
	if ba.size() != 2 or str(ba[0]) != "往返" or str(ba[1]) != "往返点":
		print("FAIL T8 roundtrip: aliases=", ba, " 期望 [往返, 往返点]")
		return false
	print("PASS T8 roundtrip")
	return true


# ─── T9 §5.3-7-9 Delete 后 Count-1、重载仍无 ────────────────

func _test_delete() -> bool:
	var m = _fresh()
	_seed(m, {"id": "del_a", "name": "删A", "gx": 1, "gy": 1})
	_seed(m, {"id": "del_b", "name": "删B", "gx": 2, "gy": 2})
	if m.Count() != 2:
		print("FAIL T9 delete: 准备阶段 Count=", m.Count(), " 期望 2")
		return false
	if not m.Delete("del_a"):
		print("FAIL T9 delete: Delete(del_a) 返回 false")
		return false
	if m.Count() != 1:
		print("FAIL T9 delete: 删后 Count=", m.Count(), " 期望 1")
		return false
	if m.Delete("nobody"):
		print("FAIL T9 delete: 不存在的 id 应返回 false")
		return false
	var m2 = PlaceMapScript.new(TEST_PATH)
	var _lr2: Dictionary = m2.Load()
	if m2.Count() != 1:
		print("FAIL T9 delete: 重载后 Count=", m2.Count(), " 期望 1")
		return false
	if bool(m2.Resolve("删A")["ok"]):
		print("FAIL T9 delete: 重载后 del_a 仍在表里")
		return false
	if not bool(m2.Resolve("删B")["ok"]):
		print("FAIL T9 delete: 重载后 del_b 不该丢")
		return false
	print("PASS T9 delete")
	return true


# ─── T10 §5.3-7-10 Nearest 命中最近 + dist_m 手算 ±0.01 ─────

func _test_nearest() -> bool:
	var m = _fresh()
	_seed(m, {"id": "park_south_gate", "name": "公园南门", "gx": 128, "gy": 80})   # 格心 (64.25, 40.25)
	_seed(m, {"id": "far_point", "name": "远点", "gx": 200, "gy": 200})            # 格心 (100.25, 100.25)
	var r: Dictionary = m.Nearest(65.0, 41.0)
	if not bool(r["ok"]):
		print("FAIL T10 nearest: ok=false ", r)
		return false
	if str(r["id"]) != "park_south_gate" or str(r["name"]) != "公园南门":
		print("FAIL T10 nearest: id/name=", r["id"], "/", r["name"])
		return false
	# 手算：sqrt((65.0-64.25)^2 + (41.0-40.25)^2) = sqrt(0.5625+0.5625) = 1.0606602
	if not _near(float(r["dist_m"]), 1.0606602, 0.01):
		print("FAIL T10 nearest: dist_m=", r["dist_m"], " 期望 ≈1.0607（±0.01）")
		return false
	# 超出 max_range：仍回最近那条，但 ok=false / out_of_range
	var r2: Dictionary = m.Nearest(65.0, 41.0, 0.5)
	if bool(r2["ok"]) or str(r2["error"]) != "out_of_range":
		print("FAIL T10 nearest: 半径 0.5 应 out_of_range ", r2)
		return false
	if str(r2["id"]) != "park_south_gate" or not _near(float(r2["dist_m"]), 1.0606602, 0.01):
		print("FAIL T10 nearest: out_of_range 也要回候选 ", r2)
		return false
	# 非有限坐标 → bad_coord
	var r3: Dictionary = m.Nearest(INF, 0.0)
	if bool(r3["ok"]) or str(r3["error"]) != "bad_coord":
		print("FAIL T10 nearest: INF 输入应 bad_coord ", r3)
		return false
	print("PASS T10 nearest")
	return true


# ─── T11 §5.3-7-11 layer 过滤 ─────────────────────────────

func _test_layer_filter() -> bool:
	var m = _fresh()
	_seed(m, {"id": "p1", "name": "地点一", "gx": 10, "gy": 10})
	_seed(m, {"id": "z1", "name": "区域一", "layer": "zone", "gx": 20, "gy": 20})
	var places: Array = m.All("place")
	if places.size() != 1:
		print("FAIL T11 layer_filter: All(\"place\").size()=", places.size(), " 期望 1")
		return false
	if str(places[0]["id"]) != "p1":
		print("FAIL T11 layer_filter: All(\"place\") 含非 place 条目 =", places[0]["id"])
		return false
	var every: Array = m.All()
	if every.size() != 2:
		print("FAIL T11 layer_filter: All().size()=", every.size(), " 期望 2")
		return false
	var has_zone := false
	for row: Dictionary in every:
		if str(row["id"]) == "z1":
			has_zone = true
	if not has_zone:
		print("FAIL T11 layer_filter: All() 不含 zone 条目")
		return false
	if m.Count("place") != 1 or m.Count("zone") != 1 or m.Count() != 2:
		print("FAIL T11 layer_filter: Count place/zone/全部=", m.Count("place"), "/", m.Count("zone"), "/", m.Count())
		return false
	print("PASS T11 layer_filter")
	return true


# ─── T12 §5.3-7-12 坏 JSON → parse_error 且 Count 不变 ──────

func _test_bad_json() -> bool:
	var m = _fresh()
	_seed(m, {"id": "keep_a", "name": "保留A", "gx": 5, "gy": 5})
	_seed(m, {"id": "keep_b", "name": "保留B", "gx": 6, "gy": 6})
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if f == null:
		print("FAIL T12 bad_json: 打不开测试文件 ", TEST_PATH)
		return false
	f.store_string("{ 这不是 JSON ,,, ")
	f.close()
	var r: Dictionary = m.Load()
	if bool(r["ok"]):
		print("FAIL T12 bad_json: ok 非 false ", r)
		return false
	if str(r["error"]) != "parse_error":
		print("FAIL T12 bad_json: error=", r["error"], " 期望 parse_error")
		return false
	if m.Count() != 2:
		print("FAIL T12 bad_json: Count=", m.Count(), " 期望 2（内存原样、不崩）")
		return false
	if m.All().size() != 2:
		print("FAIL T12 bad_json: All().size()=", m.All().size(), " 期望 2")
		return false
	# 坏文件不该被这次 Load 覆盖成空表：再查一次仍能 Resolve 到旧条目
	if not bool(m.Resolve("保留A")["ok"]):
		print("FAIL T12 bad_json: 坏 JSON 之后内存条目丢了")
		return false
	print("PASS T12 bad_json")
	return true
