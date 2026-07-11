extends SceneTree
## Present by KeJi
## Date: 2026-07-11
##
## 生成 map_chunk_0_0.tres（随机 0/1）

const SIZE := 256
const OUT_DIR := "user://map_data_2d/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var script := load("res://src/renderer_2d/chunk_data_2d.gd")
	var chunk: Resource = script.new()
	var cells := PackedByteArray()
	cells.resize(SIZE * SIZE)
	for i in range(SIZE * SIZE):
		cells[i] = randi() % 2
	chunk.set("cells", cells)

	var path := OUT_DIR + "map_chunk_0_0.tres"
	var err := ResourceSaver.save(chunk, path)
	if err == OK:
		print("[gen] saved: ", path)
	else:
		printerr("[gen] failed: ", err)
	quit()
