## Presented by KeJi
## Created Date ： 2026-11-12
## Modified Date ： 2026-11-12
##
## PlaceMap — 语义层（task_51 Step 4 §5.3）：把某个栅格点命名成「公园南门」
##
## 几何层（MapData2D 的 log-odds 栅格）之上的一层「地名表」：只存 id / 名字 / 格号 / 半径，
## 不碰栅格、不碰 chunk、不发协议。调用方自己 new() 出来持有（无 Autoload、无场景、无 _ready）。
##
## ⚠️ 为什么语义点不能写进 chunk（三条，缺一不可）：
##   ① 语义不同：chunk 存的是 log-odds（i8），ChunkData2D.to_state 会把它派生成
##      free / occupied / unknown 三态；「公园南门」写进去只会变成一格的障碍概率，语义被抹平。
##   ② 会广播出去：chunk 走 CRDT —— map_delta 经 gossipsub 发给全集群，车端合并后会拿去规划，
##      地名于是变成车端眼里的障碍物。
##   ③ 粒度不匹配：栅格是 0.5 m 一格，地点是「一个门口 / 一个区域」；一格里装不下 radius，
##      更装不下 aliases 这种文本。格是观测的最小单位，不是命名的单位。
##
## ⚠️ 为什么落盘用 user:// 而不是 res://：
##   导出后 res:// 在 PCK 内只读 —— 编辑器里能写、导出后必失败。同仓现成先例：
##   src/renderer_2d/map_data_2d.gd:10 `const SAVE_DIR := "user://map_data_2d/"`。
##   （任务文档 §5.3-6 提到的「audio_input.gd 已有这个坑」已过时：该文件 Task 27 起改成内存转发、
##     不再落盘，见 src/control/audio_input.gd:9，不能再当先例引用。）
##
## ⚠️ 坐标口径（与 Rust 逐字一致，本文件不自己推公式）：
##   米 → 格：CoordUtils.game_to_tile(CoordUtils.real_to_game(x, y)) ≡ floor(x / 0.5)
##      （pleiades-base/src/Robot/core/grid.rs:254 world_to_grid）
##   格 → 米（格中心）：CoordUtils.tile_to_real(gx, gy) ≡ (g + 0.5) * 0.5
##      （pleiades-ugv/src/ugv/executor.rs:143 cell_center；ProtocolDef.MAP_RESOLUTION = 0.5）
##   gx/gy 是主键、x/y 一律由 Cell_Center(gx, gy) 派生：同一格只有一种坐标写法。
##   下发任务时 x/y 作为 Goto/Face 的世界坐标交给执行器（task_45 起执行器走 Point 口径、不取格心，
##   见 Architecture/robot_arch.md §8.15）；本层只保证「同一格唯一坐标」，不改执行器口径。
##
## ⚠️ Load 宽松、Set 严格（§5.3-6）：手写 JSON 必然省字段 → Load 补默认、单条非法跳过并计数；
##   Set 是写入闸门 → 七类校验全拒，不静默修正（不改 id 大小写、不改 name、不夹 radius）。

class_name PlaceMap
extends RefCounted

## 持久化格式版本：{"version": 1, "entries": [...]}
const VERSION := 1

## 缺省落盘路径：user://（见文件头），导出后仍可写
const DEFAULT_PATH := "user://place_map.json"

## 缺省语义层名；格界 = 世界 128 m ÷ 0.5 m = 256 格。
## MAX_CELL 不写成 `ProtocolDef.MAP_WIDTH`：常量表达式跨类引用有编译期风险；
## 改为字面量 + 单测 T0 与 ProtocolDef 对齐（同 map_api.gd 的 WORLD_SIZE_M 做法）。
const DEFAULT_LAYER := "place"
const MAX_CELL := 256

## Set 的七类 error（§5.3-4），外加 Resolve/Nearest/落盘用的四个
const ERR_BAD_ID := "bad_id"
const ERR_BAD_LAYER := "bad_layer"
const ERR_BAD_NAME := "bad_name"
const ERR_BAD_ALIAS := "bad_alias"
const ERR_BAD_RADIUS := "bad_radius"
const ERR_BAD_COORD := "bad_coord"
const ERR_OUT_OF_BOUNDS := "out_of_bounds"
const ERR_PARSE := "parse_error"
const ERR_READ := "read_error"
const ERR_NOT_FOUND := "not_found"
const ERR_OUT_OF_RANGE := "out_of_range"

var _path: String = DEFAULT_PATH
var _entries: Dictionary = {}      # id(String) → entry(Dictionary)


## 只记路径，不读盘（读盘由调用方 Load() 决定）
func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


# ─── 坐标换算（三个静态方法，全部复用 CoordUtils，不写公式） ──────

## 米 → 格（floor 口径，与 grid.rs world_to_grid 一致）
static func Cell_From_Meters(x: float, y: float) -> Vector2i:
	return CoordUtils.game_to_tile(CoordUtils.real_to_game(x, y))


## 游戏像素 → 格（鼠标选点用；AutoHandler 右键已在走同一条链）
static func Cell_From_Game_Pixel(p: Vector2) -> Vector2i:
	return CoordUtils.game_to_tile(p)


## 格 → 米（格中心，(g + 0.5) * 0.5，与 executor.rs cell_center 一致）
static func Cell_Center(gx: int, gy: int) -> Vector2:
	return CoordUtils.tile_to_real(gx, gy)


# ─── 持久化 ───────────────────────────────────────────────

## 读盘：宽松。文件不存在 = 空表（ok=true）；坏 JSON = parse_error 且内存原样。
## 返回 {ok, count, skipped, error}
func Load() -> Dictionary:
	if not FileAccess.file_exists(_path):
		_entries.clear()
		return {"ok": true, "count": 0, "skipped": 0, "error": ""}
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "count": _entries.size(), "skipped": 0, "error": ERR_READ}
	var text := f.get_as_text()
	f.close()
	# 必须用 JSON.new().parse()：JSON.parse_string 会把 ERROR 打到 stderr（ws_command_server.gd:28 先例）
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "count": _entries.size(), "skipped": 0, "error": ERR_PARSE}
	var data: Variant = json.data
	if not (data is Dictionary):
		return {"ok": false, "count": _entries.size(), "skipped": 0, "error": ERR_PARSE}
	var root: Dictionary = data
	var rows: Variant = root.get("entries", [])
	if not (rows is Array):
		return {"ok": false, "count": _entries.size(), "skipped": 0, "error": ERR_PARSE}
	var loaded := {}
	var skipped := 0
	for raw: Variant in rows:
		var e: Variant = _normalize_lenient(raw)
		if e == null:
			skipped += 1
			continue
		var entry: Dictionary = e
		loaded[str(entry["id"])] = entry
	# 只有全部读通才整体替换（parse_error / read_error 时内存原样）
	_entries = loaded
	return {"ok": true, "count": _entries.size(), "skipped": skipped, "error": ""}


## 读盘覆盖内存（手改文件后由调用方显式调用；不做文件监听）
func Reload() -> Dictionary:
	return Load()


## 落盘：{"version": 1, "entries": [...]}，键序稳定（JSON.stringify 默认 sort_keys=true，缩进 \t）
func Save() -> bool:
	var rows: Array = []
	var ids := _entries.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = _entries[id]
		rows.append(e.duplicate(true))
	var text := JSON.stringify({"version": VERSION, "entries": rows}, "\t")
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_warning("[PlaceMap] Save 打开失败：%s（%s）" % [_path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.close()
	return true


# ─── 查询 ─────────────────────────────────────────────────

## 条数；layer 为空 = 全部（精确匹配）
func Count(layer: String = "") -> int:
	if layer.is_empty():
		return _entries.size()
	var n := 0
	for id: String in _entries:
		if str(_entries[id]["layer"]) == layer:
			n += 1
	return n


## 全部条目（深拷贝，按 id 升序；layer 为空 = 全部）
func All(layer: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := _entries.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = _entries[id]
		if not layer.is_empty() and str(e["layer"]) != layer:
			continue
		out.append(e.duplicate(true))
	return out


# ─── 写入 ─────────────────────────────────────────────────

## 写入一条（严格）：七类校验全拒 → {ok:false, error, entry:{}, saved:false}
## 成功 → 内存替换该 id 整条 + 立即 Save()，返回 {ok:true, error:"", entry, saved}
func Set(entry: Dictionary) -> Dictionary:
	var checked := _validate(entry)
	if not bool(checked["ok"]):
		return {"ok": false, "error": str(checked["error"]), "entry": {}, "saved": false}
	var norm: Dictionary = checked["entry"]
	_entries[str(norm["id"])] = norm
	var saved := Save()
	return {"ok": true, "error": "", "entry": norm.duplicate(true), "saved": saved}


## 删除一条：true ⇔ 该 id 原先存在且已从内存删掉（落盘失败只告警）
func Delete(id: String) -> bool:
	if not _entries.has(id):
		return false
	var _removed: bool = _entries.erase(id)
	if not Save():
		push_warning("[PlaceMap] Delete(%s) 已从内存删除，但落盘失败" % id)
	return true


# ─── 解析与就近 ───────────────────────────────────────────

## 归一化（strip_edges + to_lower）后按 id → name → aliases 匹配；
## 同优先级命中多条取 id 字典序最小，并把全部命中塞进 ambiguous（不静默丢弃）。
## 返回 11 键：{ok, id, name, x, y, gx, gy, layer, matched_alias, ambiguous, error}
func Resolve(text: String) -> Dictionary:
	var result := {
		"ok": false, "id": "", "name": "", "x": 0.0, "y": 0.0,
		"gx": 0, "gy": 0, "layer": "", "matched_alias": "",
		"ambiguous": [], "error": ERR_NOT_FOUND,
	}
	var key := text.strip_edges().to_lower()
	if key.is_empty():
		return result
	var ids := _match_by_id(key)
	var alias := ""
	if ids.is_empty():
		ids = _match_by_name(key)
	if ids.is_empty():
		var found := _match_by_alias(key)
		var found_ids: Array = found["ids"]
		for fid: Variant in found_ids:
			ids.append(str(fid))
		var alias_of: Dictionary = found["alias_of"]
		if not ids.is_empty():
			alias = str(alias_of.get(str(ids[0]), ""))
	if ids.is_empty():
		return result
	var chosen := str(ids[0])
	var e: Dictionary = _entries[chosen]
	result["ok"] = true
	result["error"] = ""
	result["id"] = chosen
	result["name"] = str(e["name"])
	result["x"] = float(e["x"])
	result["y"] = float(e["y"])
	result["gx"] = int(e["gx"])
	result["gy"] = int(e["gy"])
	result["layer"] = str(e["layer"])
	result["matched_alias"] = alias
	result["ambiguous"] = ids.duplicate() if ids.size() > 1 else []
	return result


## 最近点：按格中心算欧氏距离，并列取 id 字典序最小；max_range < 0 = 不限。
## 返回 {ok, id, name, dist_m, error}
func Nearest(x: float, y: float, max_range: float = 3.0, layer: String = "") -> Dictionary:
	var result := {"ok": false, "id": "", "name": "", "dist_m": -1.0, "error": ERR_NOT_FOUND}
	if not is_finite(x) or not is_finite(y):
		result["error"] = ERR_BAD_COORD
		return result
	var limit := max_range
	if limit < 0.0:
		limit = INF
	var target := Vector2(x, y)
	var best_id := ""
	var best_dist := INF
	for id: String in _entries:
		var e: Dictionary = _entries[id]
		if not layer.is_empty() and str(e["layer"]) != layer:
			continue
		var d := target.distance_to(Vector2(float(e["x"]), float(e["y"])))
		if d < best_dist - 1e-9:
			best_dist = d
			best_id = id
		elif absf(d - best_dist) <= 1e-9 and id < best_id:
			best_id = id
	if best_id.is_empty():
		return result
	result["id"] = best_id
	result["name"] = str(_entries[best_id]["name"])
	result["dist_m"] = best_dist
	if best_dist > limit:
		result["error"] = ERR_OUT_OF_RANGE
		return result
	result["ok"] = true
	result["error"] = ""
	return result


# ─── 严校验（Set 专用，七类；Load 不用它） ────────────────────

static func _validate(src: Dictionary) -> Dictionary:
	# ① id：String、非空、[a-z0-9_-]、≤ 64（不 to_lower：归一化只在 Resolve 查询侧）
	var raw_id: Variant = src.get("id", null)
	if not (raw_id is String):
		return _fail(ERR_BAD_ID)
	var id: String = raw_id
	if not _is_valid_id(id):
		return _fail(ERR_BAD_ID)
	# ② layer：缺省/空串 = place；非空必须 [a-z0-9_] 且 ≤ 32
	var raw_layer: Variant = src.get("layer", "")
	if not (raw_layer is String):
		return _fail(ERR_BAD_LAYER)
	var layer: String = raw_layer
	layer = layer.strip_edges()
	if layer.is_empty():
		layer = DEFAULT_LAYER
	if not _is_valid_layer(layer):
		return _fail(ERR_BAD_LAYER)
	# ③ name：String 且 strip 后非空（不改写原值）
	var raw_name: Variant = src.get("name", null)
	if not (raw_name is String):
		return _fail(ERR_BAD_NAME)
	var name: String = raw_name
	if name.strip_edges().is_empty():
		return _fail(ERR_BAD_NAME)
	# ④ aliases：必须是 Array，每项是非空 String（数字/空串/非数组都拒）
	var raw_aliases: Variant = src.get("aliases", [])
	if not (raw_aliases is Array):
		return _fail(ERR_BAD_ALIAS)
	var aliases: Array = []
	for a: Variant in raw_aliases:
		if not (a is String):
			return _fail(ERR_BAD_ALIAS)
		var s: String = a
		if s.strip_edges().is_empty():
			return _fail(ERR_BAD_ALIAS)
		aliases.append(s)
	# ⑤ radius：数字且有限且 >= 0
	var raw_radius: Variant = _as_float(src.get("radius", 0.0))
	if raw_radius == null or float(raw_radius) < 0.0:
		return _fail(ERR_BAD_RADIUS)
	# ⑥ 坐标至少要一组（给了 gx 或 gy 就两组都得是整数；否则 x/y 都得是有限数）
	var cell: Variant = _cell_for_set(src)
	if cell == null:
		return _fail(ERR_BAD_COORD)
	var c: Vector2i = cell
	# ⑦ 格界 [0, 256)
	if c.x < 0 or c.y < 0 or c.x >= MAX_CELL or c.y >= MAX_CELL:
		return _fail(ERR_OUT_OF_BOUNDS)
	var center := Cell_Center(c.x, c.y)
	return {"ok": true, "error": "", "entry": {
		"id": id, "name": name, "aliases": aliases, "layer": layer,
		"kind": str(src.get("kind", "")),
		"gx": c.x, "gy": c.y, "x": center.x, "y": center.y,
		"radius": float(raw_radius),
		"updated_at": int(Time.get_unix_time_from_system()),
	}}


## Set 侧的坐标取值：gx/gy 优先（两组必须同时给且是整数）；否则 x/y 派生。都给不出 = null
static func _cell_for_set(src: Dictionary) -> Variant:
	if src.has("gx") or src.has("gy"):
		var gx: Variant = _as_int(src.get("gx", null))
		var gy: Variant = _as_int(src.get("gy", null))
		if gx == null or gy == null:
			return null
		return Vector2i(int(gx), int(gy))
	if not (src.has("x") or src.has("y")):
		return null
	var mx: Variant = _as_float(src.get("x", null))
	var my: Variant = _as_float(src.get("y", null))
	if mx == null or my == null:
		return null
	return Cell_From_Meters(float(mx), float(my))


## Load 侧宽松归一：id 非空即可（层名/半径/别名一律补默认），坐标按 D2 取。非法 → null
static func _normalize_lenient(raw: Variant) -> Variant:
	if not (raw is Dictionary):
		return null
	var src: Dictionary = raw
	var raw_id: Variant = src.get("id", null)
	if not (raw_id is String):
		return null
	var id: String = raw_id
	id = id.strip_edges()
	if id.is_empty():
		return null
	var cell: Variant = _cell_from_entry(src)
	if cell == null:
		return null
	var c: Vector2i = cell
	if c.x < 0 or c.y < 0 or c.x >= MAX_CELL or c.y >= MAX_CELL:
		return null
	var aliases: Array = []
	var raw_aliases: Variant = src.get("aliases", [])
	if raw_aliases is Array:
		for a: Variant in raw_aliases:
			var s := str(a).strip_edges()
			if not s.is_empty():
				aliases.append(str(a))
	var layer := str(src.get("layer", DEFAULT_LAYER)).strip_edges()
	if layer.is_empty():
		layer = DEFAULT_LAYER
	var radius := 0.0
	var raw_radius: Variant = _as_float(src.get("radius", 0.0))
	if raw_radius != null and float(raw_radius) >= 0.0:
		radius = float(raw_radius)
	var updated: Variant = _as_int(src.get("updated_at", 0))
	var ts: int = 0 if updated == null else int(updated)
	var center := Cell_Center(c.x, c.y)
	return {
		"id": id,
		"name": str(src.get("name", id)),
		"aliases": aliases,
		"layer": layer,
		"kind": str(src.get("kind", "")),
		"gx": c.x, "gy": c.y, "x": center.x, "y": center.y,
		"radius": radius,
		"updated_at": ts,
	}


## Load 侧取格：gx/gy 优先，缺了才用 x/y 派生
static func _cell_from_entry(src: Dictionary) -> Variant:
	var gx: Variant = _as_int(src.get("gx", null))
	var gy: Variant = _as_int(src.get("gy", null))
	if gx != null and gy != null:
		return Vector2i(int(gx), int(gy))
	var mx: Variant = _as_float(src.get("x", null))
	var my: Variant = _as_float(src.get("y", null))
	if mx != null and my != null:
		return Cell_From_Meters(float(mx), float(my))
	return null


# ─── 匹配与类型工具 ────────────────────────────────────────

## id 命中（大小写不敏感：按 id.to_lower() 比，所以手改文件里的大写 id 也能查）
func _match_by_id(key: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in _entries:
		if id.to_lower() == key:
			out.append(id)
	out.sort()
	return out


## name 命中（strip_edges + to_lower）
func _match_by_name(key: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in _entries:
		var e: Dictionary = _entries[id]
		if str(e["name"]).strip_edges().to_lower() == key:
			out.append(id)
	out.sort()
	return out


## alias 命中：{ids:[…], alias_of:{id: 原始别名串}}
func _match_by_alias(key: String) -> Dictionary:
	var out: Array[String] = []
	var alias_of := {}
	for id: String in _entries:
		var e: Dictionary = _entries[id]
		for a: Variant in e["aliases"]:
			if str(a).strip_edges().to_lower() == key:
				out.append(id)
				alias_of[id] = str(a)
				break
	out.sort()
	return {"ids": out, "alias_of": alias_of}


## 整数归一：int 原样；float 必须有限且是整值；其余（含 String）→ null
static func _as_int(v: Variant) -> Variant:
	if v is int:
		return int(v)
	if v is float:
		var f := float(v)
		if not is_finite(f) or floorf(f) != f:
			return null
		return int(f)
	return null


## 浮点归一：int/float 且有限；其余 → null
static func _as_float(v: Variant) -> Variant:
	if v is int:
		return float(v)
	if v is float:
		# JSON 不支持 Infinity/NaN，但手写 "1e999" 会被解析成 inf
		if not is_finite(float(v)):
			return null
		return float(v)
	return null


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code, "entry": {}}


## id 白名单：ASCII 小写字母 / 数字 / _ / -，长度 1..64（不 to_lower）
static func _is_valid_id(s: String) -> bool:
	if s.is_empty() or s.length() > 64:
		return false
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 45:
			continue
		return false
	return true


## layer 白名单：ASCII 小写字母 / 数字 / _，长度 1..32
static func _is_valid_layer(s: String) -> bool:
	if s.is_empty() or s.length() > 32:
		return false
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95:
			continue
		return false
	return true
