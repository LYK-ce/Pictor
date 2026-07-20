extends Node
## Present by KeJi
## Date: 2026-07-12
##
## WebSocketClient — WebSocket 通信组件

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
		var text := pkt.get_string_from_utf8()
		_on_message(text)


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


func _on_message(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		printerr("[WS] bad JSON: ", text.left(100))
		return

	var data = json.get_data()
	if not data is Dictionary:
		return

	var msg_type: String = data.get("type", "")

	if msg_type == "hello":
		_vehicle_id = data.get("vehicle_id", "")
		_identified = true
		print("[WS] identified as: ", _vehicle_id)
		EventBus.vehicle_registered.emit(_vehicle_id, _url)
		return

	# hello 之前的所有消息丢弃
	if not _identified:
		return

	print("[WS] msg: ", msg_type, " from ", _vehicle_id)
	match msg_type:
		"pose":
			EventBus.pose_received.emit(_vehicle_id, data)
		"map_full":
			var voxels = data.get("voxels", [])
			EventBus.map_full_received.emit(voxels)
		"map_delta":
			EventBus.map_delta_received.emit(data.get("voxels", []))


func get_state() -> int:
	return _state


func get_url() -> String:
	return _url


func get_vehicle_id() -> String:
	return _vehicle_id
