extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。启动即挂载 2D Renderer。

@export var renderer_2d_scene: PackedScene


func _ready() -> void:
	if renderer_2d_scene:
		add_child(renderer_2d_scene.instantiate())
	print("[Main] ready: ", get_child_count(), " children")
