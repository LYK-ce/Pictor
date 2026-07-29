## Presented by KeJi
## Date ： 2026-07-28
##
## TestWSServer — 多车测试用 WebSocket Server（Robot Controller 模拟）
## Manual 模式：接收 manual 命令直接控制
## Auto 模式：接收 goto 任务，模拟 Turning→Moving 闭环
## 使用时手动挂载到场景中，每车一个实例

extends Node

## 车辆标识，hello 包中发送
@export var vehicle_id := "test"

## 监听端口
@export var port := 9090

## 是否在 hello 之后发送全量地图
@export var send_map := false

## 地图资源引用，send_map 为 true 时使用
@export var map_chunk: ChunkData2D

const CHUNK_SIZE := 256

const MOVE_SPEED := 3.0          # 米/秒
const TURN_SPEED := PI           # 弧度/秒
const TURN_THRESHOLD := deg_to_rad(5.0)
const ARRIVAL_THRESHOLD := 0.3   # 米

enum OpMode { MANUAL, AUTO }
enum ExecState { IDLE, TURNING, MOVING }

enum ConnState { WAITING, HANDSHAKING, CONNECTED }

var _conn_state := ConnState.WAITING
var _server: TCPServer = null
var _peer: WebSocketPeer = null

# 运动状态
var _x := 5.0
var _y := 5.0
var _vx := 0.0
var _vy := 0.0
var _yaw := 0.0
var _turn_rate := 0.0

# 模式
var _op_mode := OpMode.AUTO
var _exec_state := ExecState.IDLE
var _goal_x := 0.0
var _goal_y := 0.0

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
	match _conn_state:
		ConnState.WAITING:
			_Try_Accept()

		ConnState.HANDSHAKING:
			_peer.poll()
			if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_conn_state = ConnState.CONNECTED
				print("[", vehicle_id, "] handshake complete")
				await get_tree().create_timer(0.5).timeout
				_Send_Hello()
				if send_map and map_chunk:
					_Send_Map()

		ConnState.CONNECTED:
			_peer.poll()
			if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				print("[", vehicle_id, "] client disconnected")
				_conn_state = ConnState.WAITING
				return
			_Read_Incoming()
			_Update_Movement(delta)
			_timer += delta
			if _timer >= 0.1:  # 10Hz
				_timer = 0.0
				_Send_Pose()


func _Update_Movement(delta: float) -> void:
	match _op_mode:
		OpMode.MANUAL:
			_x += _vx * delta
			_y += _vy * delta
			_yaw += _turn_rate * delta
		OpMode.AUTO:
			match _exec_state:
				ExecState.IDLE:
					pass  # 没有任务就停着
				ExecState.TURNING:
					_Turn_Toward_Goal(delta)
				ExecState.MOVING:
					_Move_Toward_Goal(delta)
func _Turn_Toward_Goal(delta: float) -> void:
	var target_yaw := atan2(_goal_y - _y, _goal_x - _x)
	var diff := fmod(target_yaw - _yaw + PI, TAU) - PI
	if absf(diff) < TURN_THRESHOLD:
		_yaw = target_yaw
		_exec_state = ExecState.MOVING
		return
	_yaw += signf(diff) * TURN_SPEED * delta


func _Move_Toward_Goal(delta: float) -> void:
	var dist := sqrt((_goal_x - _x) ** 2 + (_goal_y - _y) ** 2)
	if dist < ARRIVAL_THRESHOLD:
		_vx = 0.0
		_vy = 0.0
		_exec_state = ExecState.IDLE
		print("[", vehicle_id, "] arrived at (", _goal_x, ", ", _goal_y, ")")
		return
	_vx = cos(_yaw) * MOVE_SPEED
	_vy = sin(_yaw) * MOVE_SPEED
	_x += _vx * delta
	_y += _vy * delta


func _Try_Accept() -> void:
	if not _server.is_connection_available():
		return
	var tcp := _server.take_connection()
	_peer = WebSocketPeer.new()
	_peer.outbound_buffer_size = 1 << 22
	_peer.accept_stream(tcp)
	_conn_state = ConnState.HANDSHAKING
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


func _Send_Pose() -> void:
	var msg := JSON.stringify({
		"type": "pose",
		"ts": Time.get_unix_time_from_system(),
		"x": _x, "y": _y, "z": 0.0,
		"yaw": _yaw,
		"vx": _vx, "vy": _vy
	})
	_Send(msg)


func _Read_Incoming() -> void:
	while _peer.get_available_packet_count() > 0:
		var pkt := _peer.get_packet()
		if pkt.size() == 0 or not _peer.was_string_packet():
			continue
		var text := pkt.get_string_from_utf8()
		var data := Protocol.parse(text)
		if data.is_empty():
			continue

		var cmd: String = data.get("cmd", "")
		print(cmd)
		match cmd:
			"mode":
				print(data)
				_Handle_Mode(data.get("action", ""))
			"manual":
			
				if _op_mode == OpMode.MANUAL:
					
					_Handle_Manual(data.get("action", ""), data.get("speed", 0))
			"auto":
				if _op_mode == OpMode.AUTO:
					_Handle_Auto(data.get("action", ""), data.get("missions", []))


func _Handle_Mode(action: String) -> void:
	match action:
		"switch_to_auto":
			_vx = 0.0
			_vy = 0.0
			_op_mode = OpMode.AUTO
			print('switch to auto')
		"switch_to_manual":
			_vx = 0.0
			_vy = 0.0
			_op_mode = OpMode.MANUAL
			print('switch to manual')
			_exec_state = ExecState.IDLE


func _Handle_Manual(action: String, speed: int) -> void:
	print(action)
	match action:
		"forward":
			_vx = cos(_yaw) * MOVE_SPEED
			_vy = sin(_yaw) * MOVE_SPEED
		"backward":
			_vx = -cos(_yaw) * MOVE_SPEED * 0.5
			_vy = -sin(_yaw) * MOVE_SPEED * 0.5
		"spin_left":
			_vx = 0.0
			_vy = 0.0
			_turn_rate = -TURN_SPEED
		"spin_right":
			_vx = 0.0
			_vy = 0.0
			_turn_rate = TURN_SPEED
		"stop":
			_vx = 0.0
			_vy = 0.0
			_turn_rate = 0.0


func _Handle_Auto(action: String, missions: Array) -> void:
	match action:
		"push":
			if missions.size() > 0:
				var m = missions[0]
				if m.get("type", "") == "goto":
					_goal_x = m.get("x", 0.0)
					_goal_y = m.get("y", 0.0)
					_vx = 0.0
					_vy = 0.0
					_exec_state = ExecState.IDLE
					# 下一帧 auto tick 会自动从 Idle → TURNING
					_exec_state = ExecState.TURNING
					print("[", vehicle_id, "] goto (", _goal_x, ", ", _goal_y, ")")
		"cancel":
			_vx = 0.0
			_vy = 0.0
			_exec_state = ExecState.IDLE
