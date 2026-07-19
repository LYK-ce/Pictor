extends Node
## Present by KeJi
## Date: 2026-07-19
##
## TestWSServer — 测试用 WebSocket Server
## 连接后发送 map_chunk_0_0.tres 地图，并随机移动小车

const PORT := 9090
const CHUNK_SIZE := 256

var _server: TCPServer = null
var _peer: WebSocketPeer = null
var _tcp: StreamPeerTCP = null
var _connected := false
var _x := 5.0
var _y := 5.0
var _timer := 0.0


func _ready() -> void:
	_start_server()


func _start_server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(PORT)
	if err != OK:
		printerr("[TestWS] listen failed: ", err)
		return
	print("[TestWS] listening on port ", PORT)


func _process(delta: float) -> void:
	if not _connected:
		_try_accept()

	if _connected:
		_peer.poll()
		# 每秒发一次 pose，随机移动
		_timer += delta
		if _timer >= 0.5:
			_timer = 0.0
			_send_random_pose()


func _try_accept() -> void:
	if not _server.is_connection_available():
		return
	_tcp = _server.take_connection()
	_peer = WebSocketPeer.new()
	_peer.accept_stream(_tcp)
	_connected = true
	print("[TestWS] client connected")
	_send_map()


func _send(msg: String) -> void:
	_peer.send_text(msg)


func _send_map() -> void:
	var chunk: ChunkData2D = load("res://Assets/2D/map_chunk_0_0.tres")
	var cells: PackedByteArray = chunk.cells

	var voxels: Array[Dictionary] = []
	for i in range(cells.size()):
		if cells[i] == 1:
			var gx := i % CHUNK_SIZE
			var gy := i / CHUNK_SIZE
			voxels.append({
				"gx": gx, "gy": gy, "gz": 0,
				"state": 1, "conf": 1.0
			})
			# 同时发送一个 ground cell 覆盖全图（可选）
			# 只发送墙的 voxel 以减少数据量

	print("[TestWS] sending map_full: ", voxels.size(), " wall cells")
	var msg := JSON.stringify({
		"type": "map_full",
		"ts": Time.get_unix_time_from_system(),
		"voxels": voxels
	})
	_send(msg)


func _send_random_pose() -> void:
	# 随机游走
	_x += randf_range(-1.0, 1.0)
	_y += randf_range(-1.0, 1.0)
	# 限制在地图内
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
