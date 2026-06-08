extends Node
## Present by KeJi
## Date: 2026-06-08
##
## WebSocketClient — WebSocket 通信组件
## 连接小车 Pleiades，双向收发 JSON。
## 上行：收到消息 → 解析 → EventBus emit
## 下行：EventBus ctrl_send → 转发到小车

enum State { DISCONNECTED, CONNECTING, CONNECTED }

var _ws: WebSocketPeer = null
var _state := State.DISCONNECTED
var _url := "ws://192.168.1.100:9001"
var _reconnect_interval := 3.0
var _reconnect_timer := 0.0

# 待发送队列（连接中暂存，连接后发送）
var _pending_messages := []


func _ready() -> void:
	# 读取配置
	if ProjectSettings.has_setting("websocket/url"):
		_url = ProjectSettings.get_setting("websocket/url")
	if ProjectSettings.has_setting("websocket/reconnect_interval"):
		_reconnect_interval = ProjectSettings.get_setting("websocket/reconnect_interval")

	# 订阅 EventBus 下行消息
	var bus := get_node("/root/EventBus")
	bus.ctrl_send.connect(_on_ctrl_send)

	# 发起首次连接
	_connect()


func _process(delta: float) -> void:
	if _state == State.DISCONNECTED:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_connect()
		return

	if _state != State.CONNECTED:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			_state = State.CONNECTED
			print("[WS] connected")
			_flush_pending()
		elif st == WebSocketPeer.STATE_CLOSING or st == WebSocketPeer.STATE_CLOSED:
			_disconnect()
		return

	# 已连接：轮询收消息
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSING or st == WebSocketPeer.STATE_CLOSED:
		_disconnect()
		return

	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if pkt.size() == 0:
			continue
		var text := pkt.get_string_from_utf8()
		_on_message(text)


func _connect() -> void:
	_state = State.CONNECTING
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(_url)
	if err != OK:
		print("[WS] connect failed: ", err)
		_disconnect()
		return
	print("[WS] connecting to ", _url)


func _disconnect() -> void:
	_state = State.DISCONNECTED
	_reconnect_timer = _reconnect_interval
	print("[WS] disconnected, retry in ", _reconnect_interval, "s")


func _flush_pending() -> void:
	for msg in _pending_messages:
		_ws.send_text(msg)
	_pending_messages.clear()


## 收到文本消息 → 解析 JSON → 分发 EventBus
func _on_message(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		printerr("[WS] bad JSON: ", text)
		return

	var data = json.get_data()
	if not data is Dictionary:
		return

	var bus := get_node("/root/EventBus")
	match data.get("type"):
		"pose":
			bus.pose_received.emit(data)
		"voxel_full":
			var voxels = data.get("voxels", [])
			bus.voxel_received.emit(voxels, true)
		"voxel_delta":
			var voxels = data.get("voxels", [])
			bus.voxel_received.emit(voxels, false)
		"path":
			var points = data.get("points", [])
			bus.path_received.emit(points)


## EventBus ctrl_send → 发送到小车
func _on_ctrl_send(ctrl: Dictionary) -> void:
	var text := JSON.stringify(ctrl)
	if _state == State.CONNECTED:
		_ws.send_text(text)
	else:
		_pending_messages.append(text)


## 发送 JSON 字符串（供外部调用）
func send(msg: String) -> void:
	if _state == State.CONNECTED:
		_ws.send_text(msg)
	else:
		_pending_messages.append(msg)


func get_state() -> int:
	return _state


func get_url() -> String:
	return _url
