extends Node2D
## Present by KeJi
## Date: 2026-07-07
##
## MapContainer2D — 体素地图存储与双 TileMapLayer 渲染
## 底层 GroundLayer (全铺 ground)，顶层 WallLayer (障碍物 autotile)

const CELL_SIZE := 1.0  # m per grid cell
const TERRAIN_SET := 0
const TERRAIN_WALL := 0
const TERRAIN_GROUND := 1

@onready var _ground_layer := $GroundLayer as TileMapLayer
@onready var _wall_layer := $WallLayer as TileMapLayer

var _map: Dictionary = {}  # _map[gx][gz] = {"state","conf","ts","source"}


# ─── 坐标转换 ─────────────────────────────────────────────────

func world_to_tile(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))


# ─── 地图操作 ─────────────────────────────────────────────────

func set_cell(gx: int, gz: int, data: Dictionary) -> void:
	if not _map.has(gx):
		_map[gx] = {}
	_map[gx][gz] = data

	var state: int = data.get("state", 0)
	if state == 2:
		_wall_layer.set_cells_terrain_connect([Vector2i(gx, gz)], TERRAIN_SET, TERRAIN_WALL, true)


func set_full(voxels: Array) -> void:
	_map.clear()
	_wall_layer.clear()

	var ground_cells: Array[Vector2i] = []
	var wall_cells: Array[Vector2i] = []

	for v in voxels:
		var gx: int = v.get("gx", 0)
		var gz: int = v.get("gz", 0)
		var state: int = v.get("state", 0)

		if not _map.has(gx):
			_map[gx] = {}
		_map[gx][gz] = {
			"state": state,
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		}

		ground_cells.append(Vector2i(gx, gz))
		if state == 2:
			wall_cells.append(Vector2i(gx, gz))

	if not ground_cells.is_empty():
		_ground_layer.set_cells_terrain_connect(ground_cells, TERRAIN_SET, TERRAIN_GROUND, true)
	if not wall_cells.is_empty():
		_wall_layer.set_cells_terrain_connect(wall_cells, TERRAIN_SET, TERRAIN_WALL, true)


func set_delta(voxels: Array) -> void:
	for v in voxels:
		var gx: int = v.get("gx", 0)
		var gz: int = v.get("gz", 0)
		var state: int = v.get("state", 0)

		if not _map.has(gx):
			_map[gx] = {}
		_map[gx][gz] = {
			"state": state,
			"conf": v.get("conf", 1.0),
			"ts": v.get("ts", 0.0),
			"source": v.get("source", ""),
		}

		_ground_layer.set_cells_terrain_connect([Vector2i(gx, gz)], TERRAIN_SET, TERRAIN_GROUND, true)
		if state == 2:
			_wall_layer.set_cells_terrain_connect([Vector2i(gx, gz)], TERRAIN_SET, TERRAIN_WALL, true)


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
