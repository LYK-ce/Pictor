extends Node
## Present by KeJi
## Date: 2026-07-11
##
## MapData2D — 2D 地图数据节点，Chunk 分块存储
## 挂在 Main 下，unique_name_in_owner，通过 %MapData2D 全局访问

const CHUNK_SIZE := 256
const SAVE_DIR := "user://map_data_2d/"

var _chunks: Dictionary = {}  # Vector2i(chunk_x, chunk_y) → ChunkData2D


func _ready() -> void:
	EventBus.map_full_received.connect(set_full)
	EventBus.map_delta_received.connect(set_delta)


# ─── 全局入口 ─────────────────────────────────────────────────

func set_full(voxels: Array) -> void:
	print("[MapData2D] set_full: ", voxels.size(), " voxels")
	var grouped := _group_by_chunk(voxels)
	for coord in grouped:
		var cells := _dict_to_packed(grouped[coord], coord)
		set_chunk_full(coord.x, coord.y, cells)


func set_delta(voxels: Array) -> void:
	var grouped := _group_by_chunk(voxels)
	for coord in grouped:
		set_chunk_delta(coord.x, coord.y, grouped[coord])


func _group_by_chunk(voxels: Array) -> Dictionary:
	var groups := {}
	for v in voxels:
		var gx: int = v.get("gx", 0)
		var gy: int = v.get("gy", 0)
		var cx: int = floori(gx / CHUNK_SIZE)
		var cy: int = floori(gy / CHUNK_SIZE)
		var coord := Vector2i(cx, cy)
		if not groups.has(coord):
			groups[coord] = []
		var lx: int = gx - cx * CHUNK_SIZE
		var ly: int = gy - cy * CHUNK_SIZE
		groups[coord].append({"lx": lx, "ly": ly, "state": v.get("state", 0)})
	return groups


func _dict_to_packed(updates: Array, coord: Vector2i) -> PackedByteArray:
	var chunk := _get_or_create_chunk(coord.x, coord.y)
	var cells := chunk.cells
	for u in updates:
		var lx: int = u.get("lx", 0)
		var ly: int = u.get("ly", 0)
		var idx: int = ly * CHUNK_SIZE + lx
		if idx >= 0 and idx < cells.size():
			cells[idx] = u.get("state", 0)
	return cells


# ─── Chunk 级操作 ─────────────────────────────────────────────

func set_chunk_full(chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void:
	var chunk := _get_or_create_chunk(chunk_x, chunk_y)
	chunk.cells = cells
	_save_chunk(chunk_x, chunk_y, chunk)
	EventBus.chunk_updated.emit(chunk_x, chunk_y)


func set_chunk_delta(chunk_x: int, chunk_y: int, updates: Array) -> void:
	var chunk := _get_or_create_chunk(chunk_x, chunk_y)
	for u in updates:
		var lx: int = u.get("lx", 0)
		var ly: int = u.get("ly", 0)
		var idx: int = ly * CHUNK_SIZE + lx
		if idx >= 0 and idx < chunk.cells.size():
			chunk.cells[idx] = u.get("state", 0)
	_save_chunk(chunk_x, chunk_y, chunk)
	EventBus.chunk_updated.emit(chunk_x, chunk_y)


# ─── 查询 ─────────────────────────────────────────────────────

func get_cell(gx: int, gy: int) -> int:
	var cx: int = floori(gx / CHUNK_SIZE)
	var cy: int = floori(gy / CHUNK_SIZE)
	var chunk := _get_chunk(cx, cy)
	if chunk == null:
		return 0
	var lx: int = gx - cx * CHUNK_SIZE
	var ly: int = gy - cy * CHUNK_SIZE
	return chunk.cells[ly * CHUNK_SIZE + lx]


func get_chunk_cells(chunk_x: int, chunk_y: int) -> PackedByteArray:
	var chunk := _get_chunk(chunk_x, chunk_y)
	if chunk:
		return chunk.cells
	return PackedByteArray()


func load_chunk(chunk_x: int, chunk_y: int) -> PackedByteArray:
	var path := _chunk_path(chunk_x, chunk_y)
	if not ResourceLoader.exists(path):
		# 首次启动：从初始资源复制
		var initial := "res://Assets/2D/map_chunk_%d_%d.tres" % [chunk_x, chunk_y]
		if ResourceLoader.exists(initial):
			DirAccess.make_dir_recursive_absolute(SAVE_DIR)
			DirAccess.copy_absolute(initial, path)

	if ResourceLoader.exists(path):
		var chunk: ChunkData2D = ResourceLoader.load(path)
		_chunks[Vector2i(chunk_x, chunk_y)] = chunk
		return chunk.cells
	return PackedByteArray()


# ─── 内部 ─────────────────────────────────────────────────────

func _get_chunk(chunk_x: int, chunk_y: int) -> ChunkData2D:
	return _chunks.get(Vector2i(chunk_x, chunk_y), null)


func _get_or_create_chunk(chunk_x: int, chunk_y: int) -> ChunkData2D:
	var key := Vector2i(chunk_x, chunk_y)
	if not _chunks.has(key):
		var chunk := ChunkData2D.new()
		chunk.cells.resize(CHUNK_SIZE * CHUNK_SIZE)
		_chunks[key] = chunk
	return _chunks[key]


func _save_chunk(chunk_x: int, chunk_y: int, chunk: ChunkData2D) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	ResourceSaver.save(chunk, _chunk_path(chunk_x, chunk_y))


func _chunk_path(chunk_x: int, chunk_y: int) -> String:
	return SAVE_DIR + "map_chunk_%d_%d.tres" % [chunk_x, chunk_y]
