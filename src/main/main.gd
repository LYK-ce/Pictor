extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。MapData2D + Renderer2D 已挂在 tscn 中。

@export var renderer_2d_scene: PackedScene


func _ready() -> void:
	# 加载 Chunk (0,0) 并触发渲染
	var cells: PackedByteArray = %MapData2D.load_chunk(0, 0)
	if not cells.is_empty():
		EventBus.chunk_updated.emit(0, 0)

	print("[Main] ready: ", get_child_count(), " children")
