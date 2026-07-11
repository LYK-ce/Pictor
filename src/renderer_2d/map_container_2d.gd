extends Node2D
## Present by KeJi
## Date: 2026-07-11
##
## MapContainer2D — 纯渲染层，不持有地图数据
## 接收 render_chunk 调用，驱动 GroundLayer / WallLayer 重绘

const SOURCE_ID := 8
const CHUNK_SIZE := 256
const ATLAS_GROUND := Vector2i(1, 9)
const ATLAS_WALL := Vector2i(11, 6)

@onready var _ground_layer := $GroundLayer as TileMapLayer
@onready var _wall_layer := $WallLayer as TileMapLayer


func render_chunk(chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void:
	if cells.size() != CHUNK_SIZE * CHUNK_SIZE:
		return

	_wall_layer.clear()

	var offset_x: int = chunk_x * CHUNK_SIZE
	var offset_y: int = chunk_y * CHUNK_SIZE

	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var idx: int = ly * CHUNK_SIZE + lx
			var pos := Vector2i(offset_x + lx, offset_y + ly)
			if cells[idx] == 1:
				_wall_layer.set_cell(pos, SOURCE_ID, ATLAS_WALL)
			else:
				_ground_layer.set_cell(pos, SOURCE_ID, ATLAS_GROUND)
