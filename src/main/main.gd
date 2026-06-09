extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口，负责根据配置实例化子组件并组装场景。

@export var ws_scene: PackedScene
@export var ih_scene: PackedScene
@export var renderer_2d_scene: PackedScene
@export var renderer_3d_scene: PackedScene
@export var ui_scene: PackedScene


func _ready() -> void:
	if ws_scene:
		add_child(ws_scene.instantiate())
	if ih_scene:
		add_child(ih_scene.instantiate())

	var mode: String = "2d"
	if ProjectSettings.has_setting("renderer/mode"):
		mode = ProjectSettings.get_setting("renderer/mode")

	var r_scene: PackedScene = renderer_2d_scene if mode == "2d" else renderer_3d_scene
	if r_scene:
		add_child(r_scene.instantiate())
		print("[Main] Renderer mode: ", mode)
	else:
		print("[Main] Renderer not found for mode: ", mode, " — running control-only mode")

	print("[Main] ready: ", get_child_count(), " children")

	if ui_scene:
		add_child(ui_scene.instantiate())
