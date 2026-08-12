extends Node
## Presented by KeJi
## Date ： 2026-08-12
##
## WebSocketManager — 管理多个 WebSocket 连接
## 下行命令：cmd_send(vehicle_id, Dictionary) → OrionMessages.Build_Cmd 编码为帧 → send_binary
## 阶段 2：订阅 map_merged（某车 own 聚合完成）→ 返还合并全量（msgid=2）

@export var ws_client_scene: PackedScene

var _vehicles: Dictionary = {}  # {vehicle_id → WebSocketClient}，注册前用 url 当 key


func _ready() -> void:
	EventBus.ws_connect_requested.connect(create_connection)
	EventBus.ws_disconnect_requested.connect(close_connection)
	EventBus.vehicle_registered.connect(_on_vehicle_registered)
	EventBus.cmd_send.connect(_on_cmd_send)
	EventBus.map_merged.connect(_on_map_merged)


func create_connection(url: String) -> void:
	if _vehicles.has(url):
		printerr("[WS-Mgr] already connecting: ", url)
		return

	var ws: Node = ws_client_scene.instantiate()
	ws.name = url
	ws.init(url)
	ws.disconnected.connect(_on_client_disconnected.bind(ws))
	add_child(ws)
	_vehicles[url] = ws


func _on_client_disconnected(client: Node) -> void:
	for id in _vehicles:
		if _vehicles[id] == client:
			print("[WS-Mgr] client disconnected: ", id)
			_vehicles.erase(id)
			EventBus.vehicle_unregistered.emit(id)
			return


func close_connection(vehicle_id: String) -> void:
	var ws: Node = _vehicles.get(vehicle_id)
	if ws:
		ws.queue_free()
		_vehicles.erase(vehicle_id)
		EventBus.vehicle_unregistered.emit(vehicle_id)


func _on_vehicle_registered(vehicle_id: String, address: String) -> void:
	var ws = _vehicles.get(address)
	if not ws:
		return
	_vehicles.erase(address)
	_vehicles[vehicle_id] = ws
	print("[WS-Mgr] registered: ", vehicle_id, " @ ", address)


func _on_cmd_send(vehicle_id: String, cmd: Dictionary) -> void:
	var ws: Node = _vehicles.get(vehicle_id)
	if ws:
		# cmd 为 Orion 语义 Dictionary（MessageBuilder 构造）→ 编码为完整帧发送
		var frame := OrionMessages.Build_Cmd(cmd)
		if frame.is_empty():
			printerr("[WS-Mgr] cmd encode failed: ", cmd)
			return
		ws.send_binary(frame)


## 阶段 2：某车 own FULL 聚合完成 → 向该车返还当前合并全量（复用 cmd_send 下行路径）
func _on_map_merged(vehicle_id: String, _chunk_x: int, _chunk_y: int, cells: PackedByteArray) -> void:
	if not _vehicles.has(vehicle_id):
		return  # 该车已断开（own FULL 之后断链的竞态窗口），跳过返还
	EventBus.cmd_send.emit(vehicle_id, MessageBuilder.build_map_full(cells))


func get_vehicles() -> Array[String]:
	var arr: Array[String] = []
	arr.assign(_vehicles.keys())
	return arr


func get_state(vehicle_id: String) -> int:
	var ws: Node = _vehicles.get(vehicle_id)
	if ws:
		return ws.get_state()
	return WebSocketPeer.STATE_CLOSED
