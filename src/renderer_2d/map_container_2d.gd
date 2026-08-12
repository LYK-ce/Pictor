extends Node2D
## Presented by KeJi
## Date ： 2026-08-11
##
## MapContainer2D — 纯渲染层，不持有地图数据
## Task 21：接收 log-odds i8（u8 位模式），按阈值 ±6 派生三态后着色
## 接收 render_chunk 调用，驱动 GroundLayer / WallLayer 重绘

const SOURCE_ID := 0
const CHUNK_SIZE := 256
const TERRAIN_SET := 0
const TERRAIN_WALL := 0
const TERRAIN_GROUND := 1

@onready var _ground_layer := $GroundLayer as TileMapLayer
@onready var _wall_layer := $WallLayer as TileMapLayer


func render_chunk(chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void:
	if cells.size() != CHUNK_SIZE * CHUNK_SIZE:
		print("[MapContainer2D] render_chunk: chunk(%d,%d) BAD SIZE %d ≠ %d — skipping" % [chunk_x, chunk_y, cells.size(), CHUNK_SIZE * CHUNK_SIZE])
		return

	_ground_layer.clear()
	_wall_layer.clear()

	var offset_x: int = chunk_x * CHUNK_SIZE
	var offset_y: int = chunk_y * CHUNK_SIZE

	var wall_cells: Array[Vector2i] = []
	var ground_cells: Array[Vector2i] = []

	var th := ProtocolDef.LOG_ODDS_THRESHOLD
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var idx: int = ly * CHUNK_SIZE + lx
			var pos := Vector2i(offset_x + lx, offset_y + ly)
			var lg := ChunkData2D.to_i8(cells[idx])
			if lg > th:
				wall_cells.append(pos)
			elif lg < -th:
				ground_cells.append(pos)
			# 其余（含恰好 ±6）→ Unknown 不渲染

	print("[MapContainer2D] render_chunk: chunk(%d,%d) ground=%d wall=%d" % [chunk_x, chunk_y, ground_cells.size(), wall_cells.size()])

	if not ground_cells.is_empty():
		_ground_layer.set_cells_terrain_connect(ground_cells, TERRAIN_SET, TERRAIN_GROUND, true)
	if not wall_cells.is_empty():
		_wall_layer.set_cells_terrain_connect(wall_cells, TERRAIN_SET, TERRAIN_WALL, true)


func update_cells(updates: Array) -> void:
	var th := ProtocolDef.LOG_ODDS_THRESHOLD
	for u in updates:
		var gx: int = u.get("gx", 0)
		var gy: int = u.get("gy", 0)
		var lg: int = u.get("log_odds", 0)
		var pos := Vector2i(gx, gy)
		if lg > th:
			_ground_layer.erase_cell(pos)
			_wall_layer.set_cells_terrain_connect([pos], TERRAIN_SET, TERRAIN_WALL, true)
		elif lg < -th:
			_wall_layer.erase_cell(pos)
			_ground_layer.set_cells_terrain_connect([pos], TERRAIN_SET, TERRAIN_GROUND, true)
		else:
			_ground_layer.erase_cell(pos)
			_wall_layer.erase_cell(pos)
