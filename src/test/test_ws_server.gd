extends Node
## Present by KeJi
## Date: 2026-07-19
##
## TestWSServer — 多车测试用 WebSocket Server
## 连接后发 hello + map_full(可选) + pose(10Hz)

@export var vehicle_id := ""
@export var port := 9090
@export var send_map := false

const CHUNK_SIZE := 256

enum State { WAITING, HANDSHAKING, CONNECTED }
var _state := State.WAITING
var _server: TCPServer = null
var _peer: WebSocketPeer = null
var _x := 5.0
var _y := 5.0
var _timer := 0.0


func _ready() -> void:
	_start_server()


func _start_server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(port)
	if err != OK:
		printerr("[", vehicle_id, "] listen failed: ", err)
		return
	print("[", vehicle_id, "] listening on port ", port)


func _process(delta: float) -> void:
	match _state:
		State.WAITING:
			_try_accept()

		State.HANDSHAKING:
			_peer.poll()
			if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_state = State.CONNECTED
				print("[", vehicle_id, "] handshake complete")
				await get_tree().create_timer(0.5).timeout
				_send_hello()
				if send_map:
					_send_map()

		State.CONNECTED:
			_peer.poll()
			if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				print("[", vehicle_id, "] client disconnected")
				_state = State.WAITING
				return
			_timer += delta
			if _timer >= 0.1:  # 10Hz
				_timer = 0.0
				_send_random_pose()


func _try_accept() -> void:
	if not _server.is_connection_available():
		return
	var tcp := _server.take_connection()
	_peer = WebSocketPeer.new()
	_peer.outbound_buffer_size = 1 << 22
	_peer.accept_stream(tcp)
	_state = State.HANDSHAKING
	print("[", vehicle_id, "] client connecting...")


func _send(msg: String) -> void:
	var err := _peer.send_text(msg)
	if err != OK:
		printerr("[", vehicle_id, "] send_text failed: ", err)
	_peer.poll()


func _send_hello() -> void:
	var msg := JSON.stringify({
		"type": "hello",
		"vehicle_id": vehicle_id,
		"address": "ws://127.0.0.1:%d" % port
	})
	print("[", vehicle_id, "] sending hello")
	_send(msg)


func _send_map() -> void:
	var chunk: ChunkData2D = load("res://Assets/2D/map_chunk_0_0.tres")
	var cells: PackedByteArray = chunk.cells

	# 二进制帧: [type:1][chunk_x:4][chunk_y:4][cells:65536]
	var buf := PackedByteArray()
	buf.resize(9 + cells.size())
	buf[0] = 0                  # type = map_full
	buf.encode_s32(1, 0)         # chunk_x
	buf.encode_s32(5, 0)         # chunk_y
	for i in range(cells.size()):
		buf[9 + i] = cells[i]

	print("[", vehicle_id, "] sending map_full chunk(0,0), ", buf.size(), " bytes")
	_peer.put_packet(buf)
	_peer.poll()


func _send_random_pose() -> void:
	_x += randf_range(-1.0, 1.0)
	_y += randf_range(-1.0, 1.0)
	_x = clampf(_x, 2.0, CHUNK_SIZE - 2.0)
	_y = clampf(_y, 2.0, CHUNK_SIZE - 2.0)

	var msg := JSON.stringify({
		"type": "pose",
		"ts": Time.get_unix_time_from_system(),
		"x": _x, "y": _y, "z": 0.0,
		"yaw": randf_range(0.0, TAU),
		"vx": 0.0, "vy": 0.0
	})
	_send(msg)
