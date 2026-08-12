extends SceneTree
## Presented by KeJi
## Date ： 2026-08-11
##
## 生成 map_chunk_0_0.tres（确定性 log-odds 图，Task 21）
## 边界一圈 +8（Occupied）/ 中央 16×16 块 −8（Free）/ 其余 0（Unknown）
## 输出到 res://Assets/2D/（main.tscn TestWSServer.map_chunk 引用，与 test_ws_server 确定性图一致）
## 用法: godot --headless --path <项目> -s tool/gen_chunk_0_0.gd

const SIZE := 256
const OUT_PATH := "res://Assets/2D/map_chunk_0_0.tres"


func _init() -> void:
	var script := load("res://src/renderer_2d/chunk_data_2d.gd")
	var chunk: Resource = script.new()
	var cells := PackedByteArray()
	cells.resize(SIZE * SIZE)  # 全 0 = Unknown

	# 上/下边界墙 +8
	for gx in range(SIZE):
		cells[gx] = 8
		cells[(SIZE - 1) * SIZE + gx] = 8
	# 左/右边界墙 +8
	for gy in range(SIZE):
		cells[gy * SIZE] = 8
		cells[gy * SIZE + SIZE - 1] = 8
	# 中央 16×16 空地 −8（u8 位模式 0xF8）
	for gy in range(120, 136):
		for gx in range(120, 136):
			cells[gy * SIZE + gx] = (-8) & 0xFF

	chunk.set("cells", cells)

	var err := ResourceSaver.save(chunk, OUT_PATH)
	if err == OK:
		print("[gen] saved: ", OUT_PATH)
	else:
		printerr("[gen] failed: ", err)
	quit()
