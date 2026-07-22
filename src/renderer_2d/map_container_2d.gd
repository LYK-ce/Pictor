extends Node2D
## Present by KeJi
## Date: 2026-07-11
##
## MapContainer2D — 纯渲染层，不持有地图数据
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
	var unknown := 0

	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var idx: int = ly * CHUNK_SIZE + lx
			var pos := Vector2i(offset_x + lx, offset_y + ly)
			if cells[idx] == 0:
				ground_cells.append(pos)
			else:
				wall_cells.append(pos)
				if cells[idx] >= 2:
					unknown += 1

	print("[MapContainer2D] render_chunk: chunk(%d,%d) ground=%d wall=%d unknown=%d" % [chunk_x, chunk_y, ground_cells.size(), wall_cells.size() - unknown, unknown])

	if not ground_cells.is_empty():
		_ground_layer.set_cells_terrain_connect(ground_cells, TERRAIN_SET, TERRAIN_GROUND, true)
	if not wall_cells.is_empty():
		_wall_layer.set_cells_terrain_connect(wall_cells, TERRAIN_SET, TERRAIN_WALL, true)
