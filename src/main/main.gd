extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口，启动时弹菜单选择渲染模式。

@export var ws_scene: PackedScene
@export var ih_scene: PackedScene
@export var renderer_2d_scene: PackedScene
@export var renderer_3d_scene: PackedScene
@export var ui_scene: PackedScene
@export var menu_scene: PackedScene


func _ready() -> void:
	if ws_scene:
		add_child(ws_scene.instantiate())
	if ih_scene:
		add_child(ih_scene.instantiate())
	if ui_scene:
		add_child(ui_scene.instantiate())

	# 弹出菜单
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate()
		add_child(menu)
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
