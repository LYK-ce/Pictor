extends Node
## Present by KeJi
## Date: 2026-07-12
##
## WebSocketClient — WebSocket 通信组件
## 协议解析委托给 MessageParser，只负责 WS 连接管理和 EventBus 信号转发。

enum State { DISCONNECTED, CONNECTING, CONNECTED }

var _ws: WebSocketPeer = null
var _state := State.DISCONNECTED
var _url := ""
var _vehicle_id := ""
var _identified := false
var _reconnect_interval := 3.0
var _reconnect_timer := 0.0

signal connected
signal disconnected


func init(url: String) -> void:
	_url = url


func _ready() -> void:
	print("[WS] _ready url=", _url)
	_connect()


func _process(_delta: float) -> void:
	_ws.poll()

	if _state != State.CONNECTED:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_state = State.CONNECTED
			print("[WS] connected to ", _url)
			connected.emit()
			EventBus.ws_connected.emit()

	_read_packets()


func _read_packets() -> void:
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if pkt.size() == 0:
			continue
		if _ws.was_string_packet():
			var text := pkt.get_string_from_utf8()
			_on_message(text)
		else:
			# 二进制帧（hello 之后才处理）
			if not _identified:
				continue
			var result := MessageParser.parse_binary(pkt)
			if not result.ok:
				printerr("[WS] binary parse error: ", result.error)
				continue
			if result.type == ProtocolDef.BIN_MAP_FULL_TYPE:
				# DEBUG: 统计 cell 类型分布
				var cells: PackedByteArray = result.cells
				var c0 := 0; var c1 := 0; var c2 := 0
				for i in range(cells.size()):
					match cells[i]:
						0: c0 += 1
						1: c1 += 1
						2: c2 += 1
				print("[WS] map_full bin: chunk(%d,%d) cells=%d [0:%d 1:%d 2:%d]" % [result.chunk_x, result.chunk_y, cells.size(), c0, c1, c2])
				EventBus.map_full_received.emit(result.chunk_x, result.chunk_y, cells)


func _on_message(text: String) -> void:
	var result := MessageParser.parse_json(text)
	if not result.ok:
		printerr("[WS] ", result.error)
		return

	var data: Dictionary = result.data
	var msg_type: String = result.type

	if msg_type == ProtocolDef.MSG_HELLO:
		_vehicle_id = data.get("vehicle_id", "")
		_identified = true
		print("[WS] identified as: ", _vehicle_id)
		EventBus.vehicle_registered.emit(_vehicle_id, _url)
		return

	# hello 之前的所有消息丢弃
	if not _identified:
		return

	match msg_type:
		ProtocolDef.MSG_POSE:
			EventBus.pose_received.emit(_vehicle_id, data)
		ProtocolDef.MSG_MAP_DELTA:
			EventBus.map_delta_received.emit(data.get("voxels", []))


func _connect() -> void:
	_state = State.CONNECTING
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 22  # 4MB
	var err := _ws.connect_to_url(_url)
	if err != OK:
		printerr("[WS] connect failed: ", err)
		_disconnect()
		return
	print("[WS] connecting to ", _url)


func _disconnect() -> void:
	_state = State.DISCONNECTED
	_reconnect_timer = _reconnect_interval
	_identified = false
	_vehicle_id = ""
	print("[WS] disconnected from ", _url)
	disconnected.emit()


func send(msg: String) -> void:
	if _state != State.CONNECTED:
		printerr("[WS] send failed: not connected")
		return
	_ws.send_text(msg)


func get_state() -> int:
	return _state


func get_url() -> String:
	return _url


func get_vehicle_id() -> String:
	return _vehicle_id
