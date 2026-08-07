## Presented by KeJi
## Date ： 2026-08-07
##
## TestWSServer — 多车测试用 WebSocket Server（Robot Controller 模拟）
## Orion 统一协议的小车侧参考实现（GDScript）：
## - 上行：hello(JSON 过渡期) / pose(ORION_POSE) / map_full(ORION_MAP_FULL)
## - 下行：manual_control(ORION_MANUAL_CONTROL) / task_set(ORION_TASK_SET)
## Manual 模式：接收 manual 命令直接控制
## Auto 模式：接收 task_set 任务队列，模拟 Turning→Moving 闭环（整体替换语义）
## 使用时手动挂载到场景中，每车一个实例

extends Node

## 车辆标识，hello 包中发送
@export var vehicle_id := "test"

## 监听端口
@export var port := 9090

## 是否在 hello 之后发送全量地图
@export var send_map := false

## 地图资源引用，send_map 为 true 时使用（cells 编码 0/100/255）
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

# 任务队列（TASK_SET 整体替换）
var _task_queue: Array = []  # [{type, x, y}, ...]
var _goal_x := 0.0
var _goal_y := 0.0

var _timer := 0.0


func _ready() -> void:
	_Start_Server()


func _Start_Server() -> void:
	_server = TCPServer.new()
	var err := _server.listen(port)
	if err != OK:
		printerr("[" + vehicle_id + "] listen failed: ", err)
		return
	print("[" + vehicle_id + "] listening on port ", port)


func _process(delta: float) -> void:
	match _conn_state:
		ConnState.WAITING:
			_Try_Accept()

		ConnState.HANDSHAKING:
			_peer.poll()
			if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_conn_state = ConnState.CONNECTED
				print("[" + vehicle_id + "] handshake complete")
				await get_tree().create_timer(0.5).timeout
				_Send_Hello()
				if send_map and map_chunk:
					_Send_Map()

		ConnState.CONNECTED:
			_peer.poll()
			if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				print("[" + vehicle_id + "] client disconnected")
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
		print("[" + vehicle_id + "] arrived at (", _goal_x, ", ", _goal_y, ")")
		# 执行下一个任务
		if not _task_queue.is_empty():
			_task_queue.pop_front()
			_Start_Next_Task()
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
	print("[" + vehicle_id + "] client connecting...")


func _Send(msg: String) -> void:
	var err := _peer.send_text(msg)
	if err != OK:
		printerr("[" + vehicle_id + "] send_text failed: ", err)
	_peer.poll()


func _Send_Binary(frame: PackedByteArray) -> void:
	var err := _peer.put_packet(frame)
	if err != OK:
		printerr("[" + vehicle_id + "] put_packet failed: ", err)
	_peer.poll()


func _Send_Hello() -> void:
	var msg := JSON.stringify({
		"type": "hello",
		"vehicle_id": vehicle_id,
		"address": "ws://127.0.0.1:%d" % port
	})
	print("[" + vehicle_id + "] sending hello")
	_Send(msg)


func _Send_Map() -> void:
	if not map_chunk:
		printerr("[" + vehicle_id + "] map_chunk is null")
		return
	var cells: PackedByteArray = map_chunk.cells  # 已统一为 0/100/255

	var payload := OrionMessages.Encode_Map_Full(
		Time.get_ticks_msec() & 0xFFFFFFFF,
		0, 0,                      # origin_gx / origin_gy（chunk 原点全局网格坐标）
		CHUNK_SIZE, CHUNK_SIZE,    # width / height
		0.5,                       # resolution（米/cell）
		cells
	)
	var frame := OrionFrame.Encode_Frame(ProtocolDef.MSGID_MAP_FULL, 0, ProtocolDef.COMPID_VEHICLE, payload)

	print("[" + vehicle_id + "] sending map_full chunk(0,0), ", frame.size(), " bytes")
	_Send_Binary(frame)


func _Send_Pose() -> void:
	var payload := OrionMessages.Encode_Pose(
		Time.get_ticks_msec() & 0xFFFFFFFF,
		_x, _y, _vx, _vy, _yaw
	)
	var frame := OrionFrame.Encode_Frame(ProtocolDef.MSGID_POSE, 0, ProtocolDef.COMPID_VEHICLE, payload)
	_Send_Binary(frame)


func _Read_Incoming() -> void:
	while _peer.get_available_packet_count() > 0:
		var pkt := _peer.get_packet()
		if pkt.size() == 0:
			continue
		if _peer.was_string_packet():
			# 过渡期 JSON（当前无下行 JSON，仅日志）
			var text := pkt.get_string_from_utf8()
			print("[" + vehicle_id + "] json: ", text)
			continue
		var result := MessageParser.parse_orion_frame(pkt)
		if not result.ok:
			printerr("[" + vehicle_id + "] orion frame error: ", result.error)
			continue
		match result.msgid:
			ProtocolDef.MSGID_MANUAL_CONTROL:
				_Handle_Control(result.data.action, result.data.param)
			ProtocolDef.MSGID_TASK_SET:
				_Handle_Task_Set(result.data.missions)
			_:
				printerr("[" + vehicle_id + "] unhandled msgid: ", result.msgid)


func _Handle_Control(action: int, param: int) -> void:
	match action:
		ProtocolDef.ACTION_SWITCH_TO_AUTO:
			_vx = 0.0
			_vy = 0.0
			_op_mode = OpMode.AUTO
			print("[" + vehicle_id + "] switch to auto")
		ProtocolDef.ACTION_SWITCH_TO_MANUAL:
			_vx = 0.0
			_vy = 0.0
			_turn_rate = 0.0
			_op_mode = OpMode.MANUAL
			_exec_state = ExecState.IDLE
			print("[" + vehicle_id + "] switch to manual")
		_:
			if _op_mode != OpMode.MANUAL:
				return
			match action:
				ProtocolDef.ACTION_FORWARD:
					_vx = cos(_yaw) * MOVE_SPEED
					_vy = sin(_yaw) * MOVE_SPEED
					_turn_rate = 0.0
				ProtocolDef.ACTION_BACKWARD:
					_vx = -cos(_yaw) * MOVE_SPEED * 0.5
					_vy = -sin(_yaw) * MOVE_SPEED * 0.5
					_turn_rate = 0.0
				ProtocolDef.ACTION_SPIN_LEFT:
					_vx = 0.0
					_vy = 0.0
					_turn_rate = -TURN_SPEED
				ProtocolDef.ACTION_SPIN_RIGHT:
					_vx = 0.0
					_vy = 0.0
					_turn_rate = TURN_SPEED
				ProtocolDef.ACTION_STOP:
					_vx = 0.0
					_vy = 0.0
					_turn_rate = 0.0
				_:
					printerr("[" + vehicle_id + "] unknown action: ", action)


## TASK_SET 整体替换：丢弃当前队列（含正在执行的任务），从头执行新队列
## 语义对齐 Rust robot.rs：Manual 模式下静默忽略 Auto 命令（车开机默认 AUTO）
func _Handle_Task_Set(missions: Array) -> void:
	if _op_mode != OpMode.AUTO:
		print("[" + vehicle_id + "] ignore task_set: current mode is MANUAL")
		return
	_vx = 0.0
	_vy = 0.0
	_turn_rate = 0.0
	_exec_state = ExecState.IDLE
	_task_queue.clear()
	_task_queue.assign(missions)
	if _task_queue.is_empty():
		print("[" + vehicle_id + "] tasks cancelled (count=0), standby")
		return
	print("[" + vehicle_id + "] task_set received: ", _task_queue.size(), " tasks")
	_Start_Next_Task()


func _Start_Next_Task() -> void:
	if _task_queue.is_empty():
		_exec_state = ExecState.IDLE
		return
	var m: Dictionary = _task_queue[0]
	if m.get("type", -1) == ProtocolDef.MISSION_TYPE_GOTO:
		_goal_x = m.get("x", 0.0)
		_goal_y = m.get("y", 0.0)
		_exec_state = ExecState.TURNING
		print("[" + vehicle_id + "] goto (", _goal_x, ", ", _goal_y, "), queue=", _task_queue.size())
	else:
		# 未知任务类型：跳过
		_task_queue.pop_front()
		_Start_Next_Task()
