extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口，负责根据配置实例化子组件并组装场景。

func _ready() -> void:
	# 实例化 WebSocketClient
	var ws_scene := load("res://src/websocket_client/websocket_client.tscn")
	var ws: Node = ws_scene.instantiate()
	add_child(ws)

	# 实例化 InputHandler
	var ih_scene := load("res://src/input_handler/input_handler.tscn")
	var ih: Node = ih_scene.instantiate()
	add_child(ih)

	# 根据配置实例化 Renderer
	var mode: String = "2d"
	if ProjectSettings.has_setting("renderer/mode"):
		mode = ProjectSettings.get_setting("renderer/mode")

	var renderer_path := "res://src/renderer_%s/renderer_%s.tscn" % [mode, mode]
	if ResourceLoader.exists(renderer_path):
		var r_scene := load(renderer_path)
		var r: Node = r_scene.instantiate()
		add_child(r)
		print("[Main] Renderer mode: ", mode)
	else:
		print("[Main] Renderer not found: ", renderer_path, " — running control-only mode")

	print("[Main] ready: ", get_child_count(), " children")

	# 实例化 UI
	var ui_scene := load("res://src/ui/ui.tscn")
	var ui: CanvasLayer = ui_scene.instantiate()
	add_child(ui)
