extends SceneTree
## Presented by KeJi
## Created Date ： 2026-10-29
## Modified Date ： 2026-10-29
##
## WsCommandServer 自检（task_40 Step 3）：真 TCPServer + 真 WebSocketPeer 客户端 + 真 VehicleRegistry。
## 覆盖 `src/kernel/ws_command_server.gd` 的对外契约（下行 4 条命令 / 上行事件 / 订阅降频过滤 /
## 断连重连 / Stop 复监听），A7/A8 直接捕获 `EventBus.cmd_send` 判定"发了什么帧"。
##
## 用法（`--fixed-fps 60` 让 60 帧 = 引擎时间 1.0 s，降频断言才可复现）：
##   timeout 180 godot --headless --path Pictor --fixed-fps 60 -s res://tool/check_ws_command_server.gd
## 期望：total=… failed=0 + SELF-CHECK OK + EXIT=0，stderr 无 SCRIPT ERROR、无 ERROR:。
##
## 实测事实（本仓 4.7.2，写这份脚本前先探过）：
##   - `-s <脚本>` 下 **autoload 节点会实例化**（`/root/EventBus` 存在），但 `-s` 脚本自身
##     **不能直写标识符 `EventBus`**（编译期 Identifier not found）⇒ 本文件一律用
##     `root.get_node_or_null("EventBus")` 动态访问；`ws_command_server.gd` 由 `load()` 在
##     运行期编译，它内部的 `EventBus` 标识符可正常解析（已实测）。
##   - `Script.get_script_constant_map()` 可取 `BIND_ADDRESS`（A2 用它断言"只绑回环"）。
##   - TCPServer + accept_stream 在 `--headless` 下完整可用（`orion-simulation-world/src/tests/
##     check_ws_manager.gd` 的 P1/P6 同结论）。
##
## 断言编号与 tmp/task40/plan.md §4 P3 的 A1~A14 一一对应。

const SERVER_SCRIPT := "res://src/kernel/ws_command_server.gd"
const REGISTRY_SCRIPT := "res://src/vehicle_registry/vehicle_registry.gd"

## A6 注入的假车（vid 用 hex 形状，与 KernelBridge 的 `sysid.hex_encode()` 一致）。
const VID_A := "aa01"
const NAME_A := "ws_probe"
const VID_B := "bb02"
const NAME_B := "other_ugv"

## A10：60 帧 = 引擎时间 1.0 s（pose_hz=2 只该到点 2~3 次）。
const POSE_WINDOW_FRAMES := 60
## 客户端等待的上限（帧）。握手 / 收包都远小于它。
const WAIT_FRAMES := 180

var _bus: Node = null
var _registry: Node = null
var _server: Node = null
var _server_script: Script = null

var _c_peer: WebSocketPeer = null
var _c_packets: Array = []

## A7/A8/A9 的 cmd_send 捕获：{targets: Array[String], cmd: Dictionary}
var _cmd_log: Array = []

var _total: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_server_script = load(SERVER_SCRIPT) as Script
	_bus = root.get_node_or_null("EventBus")
	# ── A1 EventBus 可用（`-s` 下 autoload 是否实例化；不可用就 SKIP 而不是静默通过，plan R4）
	var ok_bus: bool = _check("A1 event-bus", _bus != null and _server_script != null,
		"EventBus=%s script=%s root_children=%d" % [
			"null" if _bus == null else "ok",
			"null" if _server_script == null else "ok", root.get_child_count()])
	if not ok_bus:
		print("[check] SKIP：`-s` 模式下 EventBus 不可用，A 组无法自检（plan R4）")
		print("SELF-CHECK SKIPPED (env: no EventBus under -s)")
		quit(3)
		return

	_registry = (_registry_script() as Script).new()
	_registry.name = "VehicleRegistry"
	root.add_child(_registry)          # 触发 registry._ready（连 EventBus）

	_server = _server_script.new()
	_server.name = "WsCommandServer"
	_server.autolisten = false         # 自检自己 `Listen(0)` 取 OS 临时端口
	root.add_child(_server)            # 触发 server._ready（连 EventBus）
	_bus.cmd_send.connect(_On_Cmd_Send)

	# ── A2 契约方法齐 + 只绑回环
	var consts: Dictionary = _server_script.get_script_constant_map()
	var methods := ["Listen", "Stop", "GetListenPort", "GetBindAddress", "IsListening", "GetStats"]
	var missing := PackedStringArray()
	for m: String in methods:
		if not _server.has_method(m):
			missing.append(m)
	_check("A2 api-surface", missing.is_empty() and str(consts.get("BIND_ADDRESS", "")) == "127.0.0.1",
		"missing=%s bind=%s" % [str(missing), str(consts.get("BIND_ADDRESS", "<缺失>"))])

	# ── A3 Listen(0) → OS 临时端口
	var err: int = _server.Listen(0)
	var port: int = _server.GetListenPort()
	_check("A3 listen-ephemeral", err == OK and port > 0 and _server.IsListening(),
		"err=%d port=%d listening=%s" % [err, port, _server.IsListening()])

	# ── A4 客户端握手成功 → 服务端 1 条连接
	var open_ok: bool = await _Client_Open(port)
	var links_ok: bool = await _Wait_Links(1)
	_check("A4 client-handshake", open_ok and links_ok,
		"open=%s links=%d" % [open_ok, _server.GetLinkCount()])

	# ── A5 vehicles（注册表空）
	var msgs: Array = await _Request({"id": 1, "cmd": "vehicles"})
	var ack: Dictionary = _Find_Ack(msgs, 1)
	var veh: Dictionary = _Find_Event(msgs, "vehicles")
	_check("A5 vehicles-empty",
		ack.get("ok", false) == true and veh.get("list", null) is Array and veh.get("list", []).is_empty(),
		"ack=%s list=%s" % [_brief(ack), _brief(veh.get("list", []))])

	# ── A6 注入注册 + peer_info → vehicles 返回 1 条且 name/node_type 正确
	_bus.vehicle_registered.emit(VID_A)
	_bus.peer_info_updated.emit(VID_A, NAME_A, "car")
	_bus.vehicle_registered.emit(VID_B)
	_bus.peer_info_updated.emit(VID_B, NAME_B, "car")
	msgs = await _Request({"id": 2, "cmd": "vehicles"})
	veh = _Find_Event(msgs, "vehicles")
	var listed: Array = veh.get("list", [])
	var row: Dictionary = {}
	for item: Dictionary in listed:
		if str(item.get("vid", "")) == VID_A:
			row = item
	_check("A6 vehicles-registered",
		listed.size() == 2 and str(row.get("name", "")) == NAME_A
		and str(row.get("node_type", "")) == "car",
		"count=%d row=%s" % [listed.size(), _brief(row)])

	# ── A7 task_set 到车名 → cmd_send 的 targets / msgid / missions 正确
	_cmd_log.clear()
	msgs = await _Request({"id": 3, "cmd": "task_set", "targets": [NAME_A],
		"missions": [{"type": 0, "x": 70.0, "y": 64.0}]})
	ack = _Find_Ack(msgs, 3)
	var one: Dictionary = _cmd_log[0] if not _cmd_log.is_empty() else {}
	var one_cmd: Dictionary = one.get("cmd", {})
	var one_targets: Array = one.get("targets", [])
	var one_m0: Dictionary = (one_cmd.get("missions", []) as Array)[0] if not (one_cmd.get("missions", []) as Array).is_empty() else {}
	_check("A7 task-set-frame",
		ack.get("ok", false) == true and one_targets.size() == 1 and str(one_targets[0]) == VID_A
		and int(one_cmd.get("msgid", -1)) == 5
		and int(one_m0.get("type", -1)) == 0
		and is_equal_approx(float(one_m0.get("x", 0.0)), 70.0)
		and is_equal_approx(float(one_m0.get("y", 0.0)), 64.0),
		"ack=%s targets=%s msgid=%s mission=%s" % [_brief(ack), str(one_targets),
			str(one_cmd.get("msgid", "<none>")), _brief(one_m0)])

	# ── A8 未注册车 → ok:false + 明确 error，且**一帧都不发**
	var before := _cmd_log.size()
	msgs = await _Request({"id": 4, "cmd": "task_set", "targets": ["ghost"],
		"missions": [{"type": 0, "x": 1.0, "y": 1.0}]})
	ack = _Find_Ack(msgs, 4)
	var ack_err := str(ack.get("error", ""))
	_check("A8 task-set-unknown",
		ack.get("ok", true) == false and ack_err.contains("unknown vehicle: ghost")
		and _cmd_log.size() == before,
		"ok=%s error=%s sent=%d(期望 %d)" % [str(ack.get("ok", "<none>")), ack_err,
			_cmd_log.size(), before])

	# ── A9 mode：auto → MANUAL_CONTROL(4) / action 9；非法 to → ok:false
	_cmd_log.clear()
	msgs = await _Request({"id": 5, "cmd": "mode", "targets": [NAME_A], "to": "auto"})
	ack = _Find_Ack(msgs, 5)
	var mode_cmd: Dictionary = (_cmd_log[0].get("cmd", {}) if not _cmd_log.is_empty() else {})
	var mode_ok: bool = ack.get("ok", false) == true and int(mode_cmd.get("msgid", -1)) == 4 \
		and int(mode_cmd.get("action", -1)) == 9
	var sent_before := _cmd_log.size()
	msgs = await _Request({"id": 6, "cmd": "mode", "targets": [NAME_A], "to": "bogus"})
	var ack_bad: Dictionary = _Find_Ack(msgs, 6)
	_check("A9 mode-frames", mode_ok and ack_bad.get("ok", true) == false and _cmd_log.size() == sent_before,
		"msgid=%s action=%s bad_ok=%s bad_err=%s" % [str(mode_cmd.get("msgid", "<none>")),
			str(mode_cmd.get("action", "<none>")), str(ack_bad.get("ok", "<none>")),
			str(ack_bad.get("error", ""))])

	# ── A10 订阅 pose_hz=2 + targets 过滤：60 帧（1.0 s）只该 2~3 帧，且只含 VID_A
	msgs = await _Request({"id": 7, "cmd": "subscribe", "events": ["pose"], "pose_hz": 2,
		"targets": [NAME_A]})
	ack = _Find_Ack(msgs, 7)
	var poses: Array = await _Emit_Poses(POSE_WINDOW_FRAMES, [VID_A, VID_B])
	var pose_a := 0
	var pose_b := 0
	for ev: Dictionary in poses:
		if str(ev.get("event", "")) != "pose":
			continue
		if str(ev.get("vid", "")) == VID_A:
			pose_a += 1
		elif str(ev.get("vid", "")) == VID_B:
			pose_b += 1
	_check("A10 pose-throttle-filter",
		ack.get("ok", false) == true and pose_a >= 2 and pose_a <= 3 and pose_b == 0,
		"ack=%s pose(%s)=%d pose(%s)=%d（窗口 %d 帧）" % [str(ack.get("ok", "<none>")),
			NAME_A, pose_a, NAME_B, pose_b, POSE_WINDOW_FRAMES])

	# ── A11 订阅关掉（events=[]）→ 不推送
	msgs = await _Request({"id": 8, "cmd": "subscribe", "events": []})
	ack = _Find_Ack(msgs, 8)
	poses = await _Emit_Poses(POSE_WINDOW_FRAMES, [VID_A])
	var pose_off := 0
	for ev: Dictionary in poses:
		if str(ev.get("event", "")) == "pose":
			pose_off += 1
	_check("A11 subscribe-off", ack.get("ok", false) == true and pose_off == 0,
		"ack=%s pose=%d（窗口 %d 帧）" % [str(ack.get("ok", "<none>")), pose_off, POSE_WINDOW_FRAMES])

	# ── A12 非法 JSON → ok:false 且不断连
	msgs = await _Request_Raw("{oops")
	ack = _Find_Ack(msgs, 0)
	_check("A12 bad-json",
		ack.get("ok", true) == false and str(ack.get("error", "")) == "bad json"
		and _server.GetLinkCount() == 1,
		"ack=%s links=%d" % [_brief(ack), _server.GetLinkCount()])

	# ── A13 断开 → 连接数归零；重连 → A5 复现
	_Client_Close()
	var drained: bool = await _Wait_Links(0)
	var reopen: bool = await _Client_Open(port)
	msgs = await _Request({"id": 9, "cmd": "vehicles"})
	ack = _Find_Ack(msgs, 9)
	var re_veh: Dictionary = _Find_Event(msgs, "vehicles")
	_check("A13 disconnect-reconnect",
		drained and reopen and ack.get("ok", false) == true
		and (re_veh.get("list", []) as Array).size() == 2,
		"drained=%s reopen=%s ack=%s count=%d" % [drained, reopen, str(ack.get("ok", "<none>")),
			(re_veh.get("list", []) as Array).size()])

	# ── A14 Stop → 端口释放且可被再监听
	_Client_Close()
	_server.Stop()
	var stopped: bool = (not _server.IsListening()) and _server.GetListenPort() == 0
	var relisten: int = _server.Listen(port)
	_check("A14 stop-relisten", stopped and relisten == OK and _server.GetListenPort() == port,
		"stopped=%s relisten_err=%d port=%d" % [stopped, relisten, _server.GetListenPort()])

	_server.Stop()
	_finish()


# ================================================================ 客户端（真 WebSocketPeer）

func _Client_Open(port: int) -> bool:
	_Client_Close()
	var peer := WebSocketPeer.new()
	peer.inbound_buffer_size = 1 << 20
	peer.outbound_buffer_size = 1 << 20
	_c_peer = peer
	_c_packets.clear()
	var err: int = peer.connect_to_url("ws://127.0.0.1:%d" % port)
	if err != OK:
		return false
	for _i in range(WAIT_FRAMES):
		await process_frame
		_Client_Poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
	return false


func _Client_Close() -> void:
	if _c_peer == null:
		return
	var state: WebSocketPeer.State = _c_peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CLOSING:
		_c_peer.close(1000, "check done")     # close() 返回 void
	_c_peer = null


func _Client_Poll() -> void:
	if _c_peer == null:
		return
	_c_peer.poll()
	var state: WebSocketPeer.State = _c_peer.get_ready_state()
	if state != WebSocketPeer.STATE_OPEN and state != WebSocketPeer.STATE_CLOSING:
		return
	while _c_peer.get_available_packet_count() > 0:
		var json := JSON.new()
		if json.parse(_c_peer.get_packet().get_string_from_utf8()) != OK:
			_c_packets.append({"event": "<bad json>", "raw": "unparsable"})
			continue
		if json.data is Dictionary:
			_c_packets.append(json.data)


## 发一条 JSON 并等 ack（`id` 命中即返回；再补 3 帧收同帧后续事件）。
func _Request(msg: Dictionary) -> Array:
	var want := int(msg.get("id", 0))
	_c_packets.clear()
	if _c_peer == null or _c_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return _c_packets.duplicate()
	_c_peer.send_text(JSON.stringify(msg))
	for _i in range(WAIT_FRAMES):
		await process_frame
		_Client_Poll()
		if not _Find_Ack(_c_packets, want).is_empty():
			break
	for _i in range(3):
		await process_frame
		_Client_Poll()
	return _c_packets.duplicate()


## 发一段原文（A12 的非法 JSON）；ack id 用 0。
func _Request_Raw(text: String) -> Array:
	_c_packets.clear()
	if _c_peer == null or _c_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return _c_packets.duplicate()
	_c_peer.send_text(text)
	for _i in range(WAIT_FRAMES):
		await process_frame
		_Client_Poll()
		if not _Find_Ack(_c_packets, 0).is_empty():
			break
	for _i in range(3):
		await process_frame
		_Client_Poll()
	return _c_packets.duplicate()


## 每帧对每个 vid 各发一帧假 pose，收 n 帧（`--fixed-fps 60` 下 n=60 即 1.0 s）。
func _Emit_Poses(frames: int, vids: Array) -> Array:
	_c_packets.clear()
	for _i in range(frames):
		for vid: String in vids:
			_bus.pose_received.emit(vid, {
				"x": 64.0, "y": 64.0, "z": 0.0, "vx": 0.0, "vy": 0.0, "yaw": 0.0,
				"valid": false, "sub_gx": 128, "sub_gy": 128, "rtk_fixed": false,
				"time_boot_ms": 0,
			})
		await process_frame
		_Client_Poll()
	return _c_packets.duplicate()


func _Wait_Links(want: int) -> bool:
	for _i in range(WAIT_FRAMES):
		if _server.GetLinkCount() == want:
			return true
		await process_frame
	return _server.GetLinkCount() == want


func _Find_Ack(msgs: Array, want_id: int) -> Dictionary:
	for msg: Dictionary in msgs:
		if msg.has("ack") and int(msg.get("ack", -1)) == want_id:
			return msg
	return {}


func _Find_Event(msgs: Array, event_name: String) -> Dictionary:
	for msg: Dictionary in msgs:
		if str(msg.get("event", "")) == event_name:
			return msg
	return {}


func _On_Cmd_Send(targets: Array[String], cmd: Dictionary) -> void:
	_cmd_log.append({"targets": targets.duplicate(), "cmd": cmd.duplicate(true)})


func _registry_script() -> Script:
	return load(REGISTRY_SCRIPT) as Script


# ================================================================ 断言与收尾

func _brief(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 120 else text.substr(0, 120) + "…"


func _check(label: String, ok: bool, detail: String = "") -> bool:
	_total += 1
	if ok:
		print("[check] ", label, " ok", (" " + detail) if not detail.is_empty() else "")
		return true
	_failed += 1
	print("[check] ", label, " FAIL", (" " + detail) if not detail.is_empty() else "")
	return false


func _finish() -> void:
	print("[check] total=", _total, " failed=", _failed)
	if _failed == 0:
		print("SELF-CHECK OK")
		quit(0)
	else:
		print("SELF-CHECK FAILED: ", _failed)
		quit(1)
