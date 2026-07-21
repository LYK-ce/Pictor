extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。MapData2D + Renderer2D + WebSocketManager + WebSocketMenu 已挂在 tscn 中。


func _ready() -> void:
	print("[Main] ready: ", get_child_count(), " children")
	_create_test_servers()


func _create_test_servers() -> void:
	var script := load("res://src/test/test_ws_server.gd") as Script

	for cfg in [
		{"id": "car_a", "port": 9090, "send_map": true},
		{"id": "car_b", "port": 9091, "send_map": false},
		{"id": "car_c", "port": 9092, "send_map": false},
	]:
		var node := Node.new()
		node.set_script(script)
		node.name = cfg.id
		node.vehicle_id = cfg.id
		node.port = cfg.port
		node.send_map = cfg.send_map
		add_child(node)
