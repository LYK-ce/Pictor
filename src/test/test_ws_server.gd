## Presented by KeJi
## Date ： 2026-08-11
##
## TestWSServer — 多车测试用 WebSocket Server（Robot Controller 模拟）
## Orion 统一协议的小车侧参考实现（GDScript）：
## - 上行：hello(JSON 过渡期) / pose(ORION_POSE) / map_full(ORION_MAP_FULL, log-odds) / map_delta(ORION_MAP_DELTA, 1Hz 聚合)
## - 下行：manual_control(ORION_MANUAL_CONTROL) / task_set(ORION_TASK_SET)
## Manual 模式：接收 manual 命令直接控制
## Auto 模式：接收 task_set 任务队列，模拟 Turning→Moving 闭环（整体替换语义）
## Task 21：地图走 log-odds 语义（确定性图：边界 +8 / 中央 16×16 −8 / 其余 0），
##          每 5 帧（1s）聚合真实差分广播 MAP_DELTA（对齐车端 robot.rs 语义）
## 使用时手动挂载到场景中，每车一个实例

extends Node

## 车辆标识，hello 包中发送
@export var vehicle_id := "test"

## 本车 peer_id（hello 中发送，hex；空 → 按 vehicle_id 自动派生确定性假值，多车互不相同）
@export var peer_id := ""

## 监听端口
@export var port := 9090

## 是否在 hello 之后发送全量地图
@export var send_map := false

## 是否发送 1Hz DELTA 流（多车 e2e 关掉保确定性；默认 true 兼容单车测试）
@export var send_delta := true

## 确定性图变体：0=上墙+中央空地(120~135)（默认）/ 1=左墙+中央空地(40~55)（两车 e2e 区分）
@export var map_variant := 0

## 地图资源引用（保留兼容；实际发送用 _Build_LogOdds_Map 确定性图，Task 21）
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

# 地图模拟（Task 21：log-odds + 1Hz 聚合 delta）
var _log_map := PackedByteArray()      # 本车 own 表（u8 位模式，65536）
var _merged_map := PackedByteArray()   # 本车 merged 表（阶段 2：终端返还 FULL 替换目标，own 保留）
var _full_rx_count := 0                # 收到终端返还 FULL 的次数（e2e 时序判定）
var _task_rx_count := 0                # 收到非空 TASK_SET 的次数（Task 22 群发 e2e 判定）
var _pending: Dictionary = {}         # {idx: 窗口净变化}（不预 clamp，同车端）
var _delta_frame := 0


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
				if send_map:
					_Send_Map()

		ConnState.CONNECTED:
			_peer.poll()
			if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				print("[" + vehicle_id + "] client disconnected")
				_conn_state = ConnState.WAITING
				return
			_Read_Incoming()
			_Update_Movement(delta)
			if send_map and send_delta and _log_map.size() == CHUNK_SIZE * CHUNK_SIZE:
				_Tick_Map_Delta()
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
	_peer.inbound_buffer_size = 1 << 22   # 接收终端返还 65KB FULL（阶段 2，默认 65535 会丢帧）
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
		"address": "ws://127.0.0.1:%d" % port,
		"peer_id": _Get_Peer_Id(),
	})
	print("[" + vehicle_id + "] sending hello")
	_Send(msg)


## 群发 TASK_SET 成员匹配用 peer_id：显式配置优先，否则按 vehicle_id 派生确定性假值（76 hex，模拟 38B Ed25519）
func _Get_Peer_Id() -> String:
	if not peer_id.is_empty():
		return peer_id
	var h := vehicle_id.md5_text()  # 32 hex，确定性
	return (h.repeat(3)).left(76)


func _Send_Map() -> void:
	var cells: PackedByteArray = _Build_LogOdds_Map()
	_log_map = cells.duplicate()     # 初始化 own 表（DELTA 聚合基准）
	_merged_map = cells.duplicate()  # 初始化 merged（单车 = own）

	var payload := OrionMessages.Encode_Map_Full(
		Time.get_ticks_msec() & 0xFFFFFFFF,
		0, 0,                      # origin_gx / origin_gy（chunk 原点全局网格坐标）
		CHUNK_SIZE, CHUNK_SIZE,    # width / height
		0.5,                       # resolution（米/cell）
		cells
	)
	var frame := OrionFrame.Encode_Frame(ProtocolDef.MSGID_MAP_FULL, PackedByteArray(), ProtocolDef.COMPID_VEHICLE, payload)

	print("[" + vehicle_id + "] sending map_full chunk(0,0), ", frame.size(), " bytes")
	_Send_Binary(frame)


## 确定性 log-odds 图：四周边界 +8（墙）/ 中央 16×16 块 −8（空地）/ 其余 0（未知）
## map_variant 0：上/下边界 +8 + 中央空地 (120~135)；variant 1：左/右边界 +8 + 中央空地 (40~55)
## 两车 e2e 用 variant 0/1 区分：重叠格 (0,0) 均为 +8 → 断言 clamp；空地不重叠
func _Build_LogOdds_Map() -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(CHUNK_SIZE * CHUNK_SIZE)
	if map_variant == 1:
		# 左/右边界墙 +8
		for gy in range(CHUNK_SIZE):
			cells[gy * CHUNK_SIZE] = 8
			cells[gy * CHUNK_SIZE + CHUNK_SIZE - 1] = 8
		for gy in range(40, 56):
			for gx in range(40, 56):
				cells[gy * CHUNK_SIZE + gx] = ChunkData2D.to_u8(-8)
	else:
		# 上/下边界墙 +8
		for gx in range(CHUNK_SIZE):
			cells[gx] = 8
			cells[(CHUNK_SIZE - 1) * CHUNK_SIZE + gx] = 8
		for gy in range(120, 136):
			for gx in range(120, 136):
				cells[gy * CHUNK_SIZE + gx] = ChunkData2D.to_u8(-8)
	return cells


## 每帧驱动地图变化（对齐车端：own 表 saturating 更新，真实差分进 pending，不预 clamp）
## 每 5 帧（1s）聚合发送一次 MAP_DELTA；覆盖正 Δ / 负 Δ / 窗口净变化超 ±8（+15）场景
func _Tick_Map_Delta() -> void:
	_delta_frame += 1
	# 区域1：中央空地内 (130,130) 每帧 −1（掠过）
	_Apply_Delta_At(130, 130, -1)
	# 区域2：中央块右侧 (140,130) 每帧 +3（命中，从 0 冲 +8）
	_Apply_Delta_At(140, 130, 3)
	# 区域3：中央块内 (125,125) 每帧 +3（命中，从 −8 起 5 帧净 +15 → 单条 Δ 超 ±8）
	_Apply_Delta_At(125, 125, 3)
	if _delta_frame % 5 == 0:
		_Flush_Pending_Delta()


func _Apply_Delta_At(gx: int, gy: int, d: int) -> void:
	var idx := gy * CHUNK_SIZE + gx
	if idx < 0 or idx >= _log_map.size():
		return
	var old := ChunkData2D.to_i8(_log_map[idx])
	var new := clampi(old + d, -ProtocolDef.LOG_ODDS_CLAMP, ProtocolDef.LOG_ODDS_CLAMP)
	var real := new - old  # 真实差分（clamp 后）
	_log_map[idx] = ChunkData2D.to_u8(new)
	# merged 同步 saturating 更新（对齐车端 grid.update 双写：own 与 merged 同源演进）
	if _merged_map.size() == CHUNK_SIZE * CHUNK_SIZE:
		var m_old := ChunkData2D.to_i8(_merged_map[idx])
		var m_new := clampi(m_old + d, -ProtocolDef.LOG_ODDS_CLAMP, ProtocolDef.LOG_ODDS_CLAMP)
		_merged_map[idx] = ChunkData2D.to_u8(m_new)
	if real != 0:
		_pending[idx] = _pending.get(idx, 0) + real


func _Flush_Pending_Delta() -> void:
	if _pending.is_empty():
		return
	var entries: Array = []
	for idx in _pending:
		var d: int = _pending[idx]
		if d != 0:  # 净 0 不发（同车端 drain 语义）
			entries.append({"gx": idx % CHUNK_SIZE, "gy": idx / CHUNK_SIZE, "delta": d})
	_pending.clear()
	if entries.is_empty():
		return
	var payload := OrionMessages.Encode_Map_Delta(Time.get_ticks_msec() & 0xFFFFFFFF, entries)
	var frame := OrionFrame.Encode_Frame(ProtocolDef.MSGID_MAP_DELTA, PackedByteArray(), ProtocolDef.COMPID_VEHICLE, payload)
	print("[" + vehicle_id + "] sending map_delta ", entries.size(), " entries (1Hz)")
	_Send_Binary(frame)


func _Send_Pose() -> void:
	var payload := OrionMessages.Encode_Pose(
		Time.get_ticks_msec() & 0xFFFFFFFF,
		_x, _y, _vx, _vy, _yaw
	)
	var frame := OrionFrame.Encode_Frame(ProtocolDef.MSGID_POSE, PackedByteArray(), ProtocolDef.COMPID_VEHICLE, payload)
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
			ProtocolDef.MSGID_MAP_FULL:
				_Handle_Map_Full(result.data)
			ProtocolDef.MSGID_MANUAL_CONTROL:
				_Handle_Control(result.data.action, result.data.param)
			ProtocolDef.MSGID_TASK_SET:
				_Handle_Task_Set(result.data)
			_:
				printerr("[" + vehicle_id + "] unhandled msgid: ", result.msgid)


## 阶段 2：模拟车端 handle_map_full —— 终端返还合并全量 → set_log_odds 替换 merged，own 保留
func _Handle_Map_Full(data: Dictionary) -> void:
	if data.chunk_x == 0 and data.chunk_y == 0 and data.width == 256 and data.height == 256 \
			and data.cells.size() == CHUNK_SIZE * CHUNK_SIZE and absf(data.resolution - 0.5) < 1e-6:
		_merged_map = data.cells.duplicate()  # set_log_odds 替换 merged
		_full_rx_count += 1
		# _log_map 不变（own 保留，对账上报数据源）
		print("[" + vehicle_id + "] received merged FULL #", _full_rx_count, " (", data.cells.size(), " cells) — merged replaced, own kept")
	else:
		printerr("[" + vehicle_id + "] merged FULL metadata mismatch — ignored: ", data)


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


## TASK_SET 整体替换（Task 22：三分支 + 成员判断，对齐车端 protocol.rs）：
## - member_count==0 → 取消全部（不检查成员）
## - member_count>0 → 本车不在 members 中 → 忽略（群发语义）
## - Manual 模式静默忽略 Auto 命令（车开机默认 AUTO）
func _Handle_Task_Set(data: Dictionary) -> void:
	if _op_mode != OpMode.AUTO:
		print("[" + vehicle_id + "] ignore task_set: current mode is MANUAL")
		return
	var missions: Array = data.missions
	var member_count: int = data.member_count
	if member_count > 0:
		var my_bytes := _Get_Peer_Id().hex_decode()
		var is_member := false
		for m in data.members:
			if m == my_bytes:
				is_member = true
				break
		if not is_member:
			print("[" + vehicle_id + "] ignore task_set: not in members")
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
	_task_rx_count += 1
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


# ─── e2e 断言辅助（阶段 2）──────────────────────────────────

func get_own_cells() -> PackedByteArray:
	return _log_map.duplicate()


func get_merged_cells() -> PackedByteArray:
	return _merged_map.duplicate()


func get_task_rx_count() -> int:
	return _task_rx_count


func get_full_rx_count() -> int:
	return _full_rx_count
