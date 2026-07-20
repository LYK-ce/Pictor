extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。MapData2D + Renderer2D + WebSocketManager + WebSocketMenu 已挂在 tscn 中。


func _ready() -> void:
	print("[Main] ready: ", get_child_count(), " children")

	# 启动内嵌 Mock Server 并自动连接
	var test_server := _create_test_server()
	add_child(test_server)
	await get_tree().process_frame
	EventBus.ws_connect_requested.emit("ws://127.0.0.1:9090")


func _create_test_server() -> Node:
	var script := load("res://src/test/test_ws_server.gd") as Script
	var node := Node.new()
	node.set_script(script)
	node.name = "TestWSServer"
	return node
