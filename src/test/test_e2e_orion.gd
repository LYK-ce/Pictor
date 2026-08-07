extends SceneTree

## Orion 协议端到端测试（headless）：
## TestWSServer(模拟小车) ← WS ← 客户端（本脚本）
## 链路验证：hello → pose(帧) → map_full(帧) → manual_control → task_set(队列替换+顺序) → cancel
## 语义（对齐 Rust）：车默认 AUTO；Manual 模式下 task_set 被忽略
## 用法: godot --headless --path <项目> -s <本脚本路径>

const URL := "ws://127.0.0.1:9090"

var _server: Node = null
var _client: WebSocketPeer = null
var _state := 0
var _t := 0.0
var _phase_t := 0.0
var _failures: Array[String] = []

var _got_hello := false
var _pose_count := 0
var _map_ok := false
var _sent_manual := false
var _manual_moving := false
var _sent_task := false
var _task_running := false
var _arrived_1 := false   # 到达 mission1 (10,10)
var _arrived_2 := false   # 之后到达 mission2 (12,12)（队列顺序验证）
var _sent_cancel := false
var _cancel_stopped := false
var _start_x := 5.0
var _start_y := 5.0
var _stop_x := 0.0
var _stop_y := 0.0


func _initialize() -> void:
	_server = load("res://src/test/test_ws_server.gd").new()
	_server.vehicle_id = "car_0"
	_server.port = 9090
	_server.send_map = true
	_server.map_chunk = load("res://Assets/2D/map_chunk_0_0.tres")
	root.add_child(_server)
	print("[TEST] server added (car_0 @ :9090), waiting...")


func _process(delta: float) -> bool:
	_t += delta
	_phase_t += delta
	match _state:
		0:  # 等待服务器监听 → 连接
			if _t > 0.6:
				_client = WebSocketPeer.new()
				_client.inbound_buffer_size = 1 << 22  # 4MB（map_full 65KB 超默认 64KB）
				_client.connect_to_url(URL)
				_state = 1
				_phase_t = 0.0
				print("[TEST] connecting...")
		1:  # 收 hello/pose/map → 切 manual + forward 验证手动控制
			_Poll_Client()
			if _got_hello and _map_ok and _pose_count > 2 and not _sent_manual:
				_sent_manual = true
				# 模拟小车默认 AUTO：先切 manual 再 forward
				_client.put_packet(OrionMessages.Build_Cmd(MessageBuilder.build_mode_switch_to_manual()))
				_client.put_packet(OrionMessages.Build_Cmd(MessageBuilder.build_manual_forward(80)))
				print("[TEST] sent switch_to_manual + manual_control(forward, 80)")
			if _manual_moving:
				_state = 2
				_phase_t = 0.0
				print("[TEST] manual OK — switch back to AUTO, sending task_set x2")
				# 车现在在 MANUAL 模式（task_set 会被忽略），先切回 AUTO
				_client.put_packet(OrionMessages.Build_Cmd(MessageBuilder.build_mode_switch_to_auto()))
				var ts := MessageBuilder.build_task_set([
					{"type": 0, "x": 10.0, "y": 10.0},
					{"type": 0, "x": 12.0, "y": 12.0},
				])
				_client.put_packet(OrionMessages.Build_Cmd(ts))
				_sent_task = true
		2:  # 等待任务执行（队列顺序：先 (10,10) 后 (12,12)）
			_Poll_Client()
			if _arrived_2 and _phase_t > 6.0 and not _sent_cancel:
				_sent_cancel = true
				_client.put_packet(OrionMessages.Build_Cmd(MessageBuilder.build_auto_cancel()))
				_state = 3
				_phase_t = 0.0
				print("[TEST] sent task_set(count=0) cancel")
		3:  # 等待取消生效（位置停止变化）
			_Poll_Client()
			if _phase_t > 2.0:
				_Finish()
	return false


func _Poll_Client() -> void:
	if _client == null:
		return
	_client.poll()
	if _client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while _client.get_available_packet_count() > 0:
		var pkt := _client.get_packet()
		if pkt.size() == 0:
			continue
		if _client.was_string_packet():
			var text := pkt.get_string_from_utf8()
			if text.contains("hello"):
				_got_hello = true
				print("[TEST] hello: ", text.left(80))
		else:
			var r := MessageParser.parse_orion_frame(pkt)
			if not r.ok:
				_failures.append("frame parse: " + r.error)
				continue
			match r.msgid:
				ProtocolDef.MSGID_POSE:
					_On_Pose(r.data)
				ProtocolDef.MSGID_MAP_FULL:
					if r.data.cells.size() == 65536 and r.data.width == 256:
						var has_100 := false
						for i in range(100):
							if r.data.cells[i] == 100:
								has_100 = true
								break
						_map_ok = has_100
						print("[TEST] map_full ok: ", r.data.cells.size(), " cells, 100-encoding=", has_100)
				_:
					print("[TEST] unexpected msgid: ", r.msgid)


func _On_Pose(data: Dictionary) -> void:
	_pose_count += 1
	if _pose_count == 1:
		_start_x = data.x
		_start_y = data.y
	if _sent_manual and not _manual_moving and absf(data.x - _start_x) > 0.05:
		_manual_moving = true
		print("[TEST] manual move detected: x=", data.x)
	if _sent_task and not _task_running and _phase_t > 0.5 and absf(data.x - _start_x) > 0.8:
		_task_running = true
		print("[TEST] task executing: x=", data.x, " y=", data.y)
	# 队列顺序断言：先接近 mission1，再接近 mission2
	if _sent_task and not _arrived_1 and Vector2(data.x, data.y).distance_to(Vector2(10.0, 10.0)) < 0.6:
		_arrived_1 = true
		print("[TEST] mission1 reached (10,10)")
	if _sent_task and _arrived_1 and not _arrived_2 and Vector2(data.x, data.y).distance_to(Vector2(12.0, 12.0)) < 0.6:
		_arrived_2 = true
		print("[TEST] mission2 reached (12,12)")
	if _sent_cancel:
		if _stop_x == 0.0 and _stop_y == 0.0:
			_stop_x = data.x
			_stop_y = data.y
		elif _phase_t > 1.0 and absf(data.x - _stop_x) < 0.05 and absf(data.y - _stop_y) < 0.05:
			_cancel_stopped = true


func _Finish() -> void:
	var ok := true
	if not _got_hello: _failures.append("no hello"); ok = false
	if not _map_ok: _failures.append("no map_full(100-encoding)"); ok = false
	if not _manual_moving: _failures.append("manual forward not moving"); ok = false
	if not _task_running: _failures.append("task_set not executing"); ok = false
	if not _arrived_1: _failures.append("mission1 (10,10) not reached"); ok = false
	if not _arrived_2: _failures.append("mission2 (12,12) not reached (queue order?)"); ok = false
	if not _cancel_stopped: _failures.append("cancel not stopping"); ok = false
	print("=== E2E result: ", "PASS" if ok else "FAIL", " ===")
	print("hello=", _got_hello, " map=", _map_ok, " manual_move=", _manual_moving,
		" task=", _task_running, " m1=", _arrived_1, " m2=", _arrived_2,
		" cancel_stop=", _cancel_stopped, " poses=", _pose_count)
	if not _failures.is_empty():
		for f in _failures:
			print("  FAIL: ", f)
	quit(0 if ok else 1)
