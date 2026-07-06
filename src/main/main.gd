extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。固定组件直接挂在 tscn 中，只动态选 Renderer。

@export var renderer_2d_scene: PackedScene
@export var renderer_3d_scene: PackedScene


func _ready() -> void:
	# 菜单选完再挂 Renderer
	var menu: CanvasLayer = $Menu
	menu.renderer_selected.connect(_on_renderer_selected)


func _on_renderer_selected(mode: String) -> void:
	match mode:
		"2d":
			if renderer_2d_scene:
				add_child(renderer_2d_scene.instantiate())
		"3d":
			if renderer_3d_scene:
				add_child(renderer_3d_scene.instantiate())
	print("[Main] Renderer mode: ", mode)
	print("[Main] ready: ", get_child_count(), " children")
