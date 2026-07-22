## Presented by KeJi
## Date ： 2026-07-22
##
## TestWSServer — 多车测试用 WebSocket Server
## 连接后发 hello + map_full(可选) + pose(10Hz)
## 使用时手动挂载到场景中，每车一个实例

extends Node

## 车辆标识，hello 包中发送
@export var vehicle_id := ""

## 监听端口
@export var port := 9090

## 是否在 hello 之后发送全量地图
@export var send_map := false

## 地图资源引用，send_map 为 true 时使用
@export var map_chunk: ChunkData2D

const CHUNK_SIZE := 256

## 最大速度（米/秒）
const MAX_SPEED := 8.0

## 加速度变化率（米/秒²），控制速度变化的剧烈程度
const ACCELERATION := 3.0

enum State { WAITING, HANDSHAKING, CONNECTED }
var _state := State.WAITING
var _server: TCPServer = null
var _peer: WebSocketPeer = null
var _x := 5.0
var _y := 5.0
var _vx := 0.0
var _vy := 0.0
var _yaw := 0.0
var _timer := 0.0


func _ready() -> void:
	_Start_Server()


func _Start_Server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(port)
	if err != OK:
		printerr("[", vehicle_id, "] listen failed: ", err)
		return
	print("[", vehicle_id, "] listening on port ", port)


func _process(delta: float) -> void:
	match _state:
		State.WAITING:
			_Try_Accept()

		State.HANDSHAKING:
			_peer.poll()
			if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_state = State.CONNECTED
				print("[", vehicle_id, "] handshake complete")
				await get_tree().create_timer(0.5).timeout
				_Send_Hello()
				if send_map and map_chunk:
					_Send_Map()

		State.CONNECTED:
			_peer.poll()
			if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				print("[", vehicle_id, "] client disconnected")
				_state = State.WAITING
				return
			_timer += delta
			if _timer >= 0.1:  # 10Hz
				_timer = 0.0
				_Send_Random_Pose()


func _Try_Accept() -> void:
	if not _server.is_connection_available():
		return
	var tcp := _server.take_connection()
	_peer = WebSocketPeer.new()
	_peer.outbound_buffer_size = 1 << 22
	_peer.accept_stream(tcp)
	_state = State.HANDSHAKING
	print("[", vehicle_id, "] client connecting...")


func _Send(msg: String) -> void:
	var err := _peer.send_text(msg)
	if err != OK:
		printerr("[", vehicle_id, "] send_text failed: ", err)
	_peer.poll()


func _Send_Hello() -> void:
	var msg := JSON.stringify({
		"type": "hello",
		"vehicle_id": vehicle_id,
		"address": "ws://127.0.0.1:%d" % port
	})
	print("[", vehicle_id, "] sending hello")
	_Send(msg)


func _Send_Map() -> void:
	if not map_chunk:
		printerr("[", vehicle_id, "] map_chunk is null")
		return
	var cells: PackedByteArray = map_chunk.cells

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


func _Send_Random_Pose() -> void:
	const DT := 0.1  # 10Hz 发送间隔

	# 随机加速度 → 速度渐变
	_vx += randf_range(-ACCELERATION, ACCELERATION) * DT
	_vy += randf_range(-ACCELERATION, ACCELERATION) * DT

	# 限速
	var speed := sqrt(_vx * _vx + _vy * _vy)
	if speed > MAX_SPEED:
		_vx = _vx / speed * MAX_SPEED
		_vy = _vy / speed * MAX_SPEED

	# 位置积分
	_x += _vx * DT
	_y += _vy * DT
	_x = clampf(_x, 2.0, CHUNK_SIZE - 2.0)
	_y = clampf(_y, 2.0, CHUNK_SIZE - 2.0)

	# yaw 平滑跟随速度方向
	if speed > 0.1:
		_yaw = lerp_angle(_yaw, atan2(_vy, _vx), 0.3)

	var msg := JSON.stringify({
		"type": "pose",
		"ts": Time.get_unix_time_from_system(),
		"x": _x, "y": _y, "z": 0.0,
		"yaw": _yaw,
		"vx": _vx, "vy": _vy
	})
	_Send(msg)
