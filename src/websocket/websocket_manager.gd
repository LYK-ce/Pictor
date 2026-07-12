extends Node
## Present by KeJi
## Date: 2026-07-12
##
## WebSocketManager — 管理多个 WebSocket 连接

@export var ws_client_scene: PackedScene

var _connections: Dictionary = {}  # String(url) → WebSocketClient


func create_connection(url: String) -> void:
	if _connections.has(url):
		printerr("[WS-Mgr] already connected: ", url)
		return

	var ws: Node = ws_client_scene.instantiate()
	ws.name = url
	ws.init(url)
	add_child(ws)
	_connections[url] = ws


func close_connection(url: String) -> void:
	var ws: Node = _connections.get(url, null)
	if ws:
		ws.queue_free()
		_connections.erase(url)


func get_connections() -> Array[String]:
	var arr: Array[String] = []
	arr.assign(_connections.keys())
	return arr


func get_state(url: String) -> int:
	var ws: Node = _connections.get(url, null)
	if ws:
		return ws.get_state()
	return WebSocketPeer.STATE_CLOSED
