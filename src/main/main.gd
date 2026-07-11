extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。挂载 MapData2D + 2D Renderer，并加载初始 Chunk。

@export var renderer_2d_scene: PackedScene
@export var map_data_2d_scene: PackedScene


func _ready() -> void:
	if map_data_2d_scene:
		add_child(map_data_2d_scene.instantiate())

	if renderer_2d_scene:
		add_child(renderer_2d_scene.instantiate())

	# 加载 Chunk (0,0) 并触发渲染
	var map: Node = %MapData2D
	var cells := map.load_chunk(0, 0)
	if not cells.is_empty():
		EventBus.chunk_updated.emit(0, 0)

	print("[Main] ready: ", get_child_count(), " children")
