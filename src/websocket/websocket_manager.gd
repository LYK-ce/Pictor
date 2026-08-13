extends Node
## Presented by KeJi
## Date ： 2026-08-12
##
## WebSocketManager — 管理多个 WebSocket 连接
## 下行命令：cmd_send(vehicle_id, Dictionary) → OrionMessages.Build_Cmd 编码为帧 → send_binary
## 阶段 2：订阅 map_merged（某车 own 聚合完成）→ 返还合并全量（msgid=2）

@export var ws_client_scene: PackedScene

var _vehicles: Dictionary = {}  # {vehicle_id → WebSocketClient}，注册前用 url 当 key
var _peer_ids: Dictionary = {}  # {vehicle_id → String(hex)}，Task 22：群发 TASK_SET 填 members（与 _vehicles 生命周期同步）


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
			_peer_ids.erase(id)
			EventBus.vehicle_unregistered.emit(id)
			return


func close_connection(vehicle_id: String) -> void:
	var ws: Node = _vehicles.get(vehicle_id)
	if ws:
		ws.queue_free()
		_vehicles.erase(vehicle_id)
		_peer_ids.erase(vehicle_id)
		EventBus.vehicle_unregistered.emit(vehicle_id)


func _on_vehicle_registered(vehicle_id: String, address: String) -> void:
	var ws = _vehicles.get(address)
	if not ws:
		return
	_vehicles.erase(address)
	_vehicles[vehicle_id] = ws
	_peer_ids[vehicle_id] = ws.get_peer_id()
	print("[WS-Mgr] registered: ", vehicle_id, " @ ", address, " peer_id=", _peer_ids[vehicle_id])


## Task 22：targets = 收件人列表（显式）；TASK_SET 由本层统一填 members（vehicle_id → peer_id 字节）
## 取消帧（missions 空）不填 members → member_count=0 → 车端取消语义
func _on_cmd_send(targets: Array[String], cmd: Dictionary) -> void:
	if cmd.get("msgid", -1) == ProtocolDef.MSGID_TASK_SET and not cmd.has("members"):
		var members: Array = []
		if not cmd.get("missions", []).is_empty():
			for id in targets:
				members.append(_Peer_Id_Bytes(id))
		cmd["members"] = members
	var frame := OrionMessages.Build_Cmd(cmd)
	if frame.is_empty():
		printerr("[WS-Mgr] cmd encode failed: ", cmd)
		return
	for id in targets:
		var ws: Node = _vehicles.get(id)
		if ws:
			ws.send_binary(frame)
		else:
			printerr("[WS-Mgr] send failed: unknown vehicle ", id)


## vehicle_id → peer_id 原始字节（hex 解码）；缺表项 → 空成员 + 警告
func _Peer_Id_Bytes(vehicle_id: String) -> PackedByteArray:
	var hex: String = _peer_ids.get(vehicle_id, "")
	if hex.is_empty():
		printerr("[WS-Mgr] no peer_id for ", vehicle_id, " — empty member")
		return PackedByteArray()
	return hex.hex_decode()


## 阶段 2：某车 own FULL 聚合完成 → 向该车返还当前合并全量（复用 cmd_send 下行路径）
func _on_map_merged(vehicle_id: String, _chunk_x: int, _chunk_y: int, cells: PackedByteArray) -> void:
	if not _vehicles.has(vehicle_id):
		return  # 该车已断开（own FULL 之后断链的竞态窗口），跳过返还
	EventBus.cmd_send.emit([vehicle_id] as Array[String], MessageBuilder.build_map_full(cells))


func get_vehicles() -> Array[String]:
	var arr: Array[String] = []
	arr.assign(_vehicles.keys())
	return arr


func get_state(vehicle_id: String) -> int:
	var ws: Node = _vehicles.get(vehicle_id)
	if ws:
		return ws.get_state()
	return WebSocketPeer.STATE_CLOSED
