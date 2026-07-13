extends Node
## Present by KeJi
## Date: 2026-06-08
##
## Main — 项目入口。MapData2D + Renderer2D + WebSocketManager 已挂在 tscn 中。


func _ready() -> void:
	print("[Main] ready: ", get_child_count(), " children")

	# 测试：连接 mock vehicle
	var mgr: Node = $WebSocketManager
	mgr.create_connection("ws://127.0.0.1:9090")
	print("[Main] connecting to ws://127.0.0.1:9090")
