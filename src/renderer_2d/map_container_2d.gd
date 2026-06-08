extends Node2D
## Present by KeJi
## Date: 2026-06-08
##
## MapContainer2D — 体素地图存储与 TileMapLayer 渲染

const CELL_SIZE := 1.0   # m per grid cell
const TILE_SIZE := Vector2i(16, 16)

# state → TileSet atlas coords (column, 0)
const TILE_COORDS := {
	0: Vector2i(0, 0),  # unknown → gray
	1: Vector2i(1, 0),  # free → black
	2: Vector2i(2, 0),  # occupied → white
}

const STATE_COLORS := {
	0: Color(0.25, 0.25, 0.25),  # gray
	1: Color(0.0, 0.0, 0.0),     # black
	2: Color(1.0, 1.0, 1.0),     # white
}

@onready var _tile_layer := $TileMapLayer as TileMapLayer
var _atlas_id := 0

var _map: Dictionary = {}   # _map[gx][gz] = {"state","conf","ts","source"}


func _ready() -> void:
	_setup_tileset()
	# TileMap 每格 16px，缩小 1/16 使 1 格 = 1 Godot unit = 1m 世界坐标
	_tile_layer.scale = Vector2(1.0 / 16.0, 1.0 / 16.0)


func _setup_tileset() -> void:
	var ts := TileSet.new()
	var source := TileSetAtlasSource.new()
	source.texture_region_size = TILE_SIZE

	# 创建一张 3×1 tile 的纹理
	var img := Image.create(TILE_SIZE.x * 3, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	for s in [0, 1, 2]:
		var sub := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
		sub.fill(STATE_COLORS[s])
		img.blit_rect(sub, Rect2i(0, 0, TILE_SIZE.x, TILE_SIZE.y), Vector2i(s * TILE_SIZE.x, 0))

	var tex := ImageTexture.create_from_image(img)
	_atlas_id = ts.add_source(source)
	source.texture = tex
	source.create_tile(TILE_COORDS[0])
	source.create_tile(TILE_COORDS[1])
	source.create_tile(TILE_COORDS[2])

	_tile_layer.tile_set = ts


# ─── 坐标转换 ─────────────────────────────────────────────────

func world_to_tile(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))


# ─── 地图操作 ─────────────────────────────────────────────────

func set_cell(gx: int, gz: int, data: Dictionary) -> void:
	if not _map.has(gx):
		_map[gx] = {}
	_map[gx][gz] = data

	# 同步更新 TileMapLayer
	var state: int = data.get("state", 0)
	var conf: float = data.get("conf", 1.0)
	_tile_layer.set_cell(Vector2i(gx, gz), _atlas_id, TILE_COORDS[state])
	# 通过 modulate 设置透明度（TileMapLayer 不支持 per-cell modulate）
	# 暂时全量渲染，置信度渲染后续优化


func set_full(voxels: Array) -> void:
	_map.clear()
	_tile_layer.clear()
	for v in voxels:
		set_cell(v.get("gx", 0), v.get("gz", 0), {
			"state": v.get("state", 0),
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		})


func set_delta(voxels: Array) -> void:
	for v in voxels:
		set_cell(v.get("gx", 0), v.get("gz", 0), {
			"state": v.get("state", 0),
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		})


func get_cell(gx: int, gz: int) -> Dictionary:
	if _map.has(gx) and _map[gx].has(gz):
		return _map[gx][gz]
	return {"state": 0, "conf": 0.0}


func get_all_cells() -> Array:
	var cells: Array = []
	for gx in _map:
		for gz in _map[gx]:
			var d: Dictionary = _map[gx][gz]
			cells.append({"gx": gx, "gz": gz, "state": d.get("state"), "conf": d.get("conf"), "ts": d.get("ts"), "source": d.get("source")})
	return cells
