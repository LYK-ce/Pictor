## Presented by KeJi
## Created Date ： 2026-10-29
## Modified Date ： 2026-11-01
##
## WsCommandServer — Pictor 的 WS 命令通道（task_40 Step 3 / 任务文档 §四）
## 让**外部 Python 进程**下发命令、读回遥测，Python 不需要懂 ORION 字节：
##   下行（Python → Pictor）：JSON 文本帧 → cmd_send（`Build_Cmd` 吃的 {msgid, ...} 形状）
##   上行（Pictor → Python）：EventBus 的 pose / peer_* / map_* → JSON
##
## 开关：命令行 `-- --ws-port=<port>`（§八 #4：默认关闭；只绑 127.0.0.1，无鉴权）。
## 默认上行：`pose` + `peer`，`pose_hz = 2`，按 `targets` 过滤（§八 #5）——10 Hz × N 车直连会变火管。
##
## 契约（docs/project_code_overview.md §九 有同一份表）：
##   下行 cmd：`vehicles` / `task_set` / `mode` / `manual` / `subscribe`
##   上行 event：`vehicles` / `pose` / `peer_connected` / `peer_info` / `peer_disconnected` / `map_delta` / `map_full`
##   `{"ack": id, "ok": true}` **只代表"已交给 kernel"**，不代表车端收到（任务文档 §四.5 ⚠️）；
##   到达判定只能用上行 pose 的 valid / gx / gy 或 sim 日志。
##
## 数据源：车名 ↔ vehicle_id 只走既有 `VehicleRegistry`（`../VehicleRegistry`，本节点父节点 = Main），
## 本节点**不维护车辆表**，只在需要时惰性解析 + is_instance_valid 复检。
##
## 写法参照 `orion-simulation-world/src/net/ComponentLink.gd` + `WebSocketManager.gd`（同仓实测）：
##   - TCPServer.listen(port, "127.0.0.1") → take_connection() → WebSocketPeer.accept_stream(tcp)
##   - 每帧 poll()；`STATE_OPEN`/`STATE_CLOSING` 都抽包，`STATE_CLOSED` 标 closed
##   - 连接缓冲必须在 accept_stream() **之前**设（连上后再改对已分配的收发缓冲无效）
##   - `WebSocketPeer.close()` 返回 void；非法 JSON 用 `JSON.new().parse()`（`JSON.parse_string` 会往 stderr 打 ERROR）
##   - 频率判定一律用 `_process(delta)` 累加的 `_now_s`，不用墙钟（`--fixed-fps` 下才可复现）

extends Node

## 只绑回环（§四.7：不做鉴权，靠"不可从外部访问"兜底）。
const BIND_ADDRESS := "127.0.0.1"
## 命令行唯一开关（§八 #4）：默认关闭，不加配置段。
const ARG_WS_PORT := "--ws-port="
const ARG_WS_PORT_BARE := "--ws-port"
## §八 #5：pose 默认 2 Hz；上限只作防御（客户端 `pose_hz<=0` = 不限频）。
const DEFAULT_POSE_HZ := 2.0
const MAX_POSE_HZ := 50.0
## map_delta 单独限频（默认不订阅；一辆车的差分是每格 9 B，直推会刷屏）。
const MAP_DELTA_HZ := 1.0
## §八 #5：默认只推 pose + peer。
const DEFAULT_EVENTS := ["pose", "peer"]
const KNOWN_EVENTS := ["pose", "peer", "map_delta", "map_full"]
## 单帧缓冲上限（`WebSocketPeer` 默认 64 KiB；命令/遥测都是小 JSON，1 MiB 足够）。
const LINK_BUFFER_BYTES := 1 << 20
## 与 Main 下的兄弟节点同名（见 `main.tscn`）：`Main/VehicleRegistry`。
const REGISTRY_PATH := "../VehicleRegistry"
const WS_CLOSE_GOING_AWAY := 1001
const FLOAT_EPS := 1e-6

## true：`_ready` 里按命令行决定是否监听（主场景用；自检置 false 后手动 `Listen(0)`）。
@export var autolisten: bool = true
## > 0 时优先于命令行（自检用）。
@export var listen_port: int = 0

var _server: TCPServer = null
var _links: Array = []
var _listen_port: int = 0
var _now_s: float = 0.0
var _next_link_id: int = 1
var _registry: Node = null
var _registry_warned: bool = false


func _ready() -> void:
	EventBus.pose_received.connect(_On_Pose_Received)
	EventBus.vehicle_registered.connect(_On_Vehicle_Registered)
	EventBus.vehicle_unregistered.connect(_On_Vehicle_Unregistered)
	EventBus.peer_info_updated.connect(_On_Peer_Info_Updated)
	EventBus.map_delta_received.connect(_On_Map_Delta_Received)
	EventBus.map_full_received.connect(_On_Map_Full_Received)
	if autolisten:
		var p := listen_port if listen_port > 0 else _Parse_Port(OS.get_cmdline_user_args())
		if p > 0:
			var err := Listen(p)
			if err != OK:
				push_warning("[WsCmd] 监听失败 port=%d（%s），通道关闭" % [p, error_string(err)])
		else:
			print("[WsCmd] 未启用（需要 `-- --ws-port=<port>`）")


func _exit_tree() -> void:
	Stop()


## 每帧：累加引擎时间 → 收新连接 → 逐条 poll → 清扫已关闭的连接。
## 没有监听也没有连接时立即返回（默认关闭时零开销）。
func _process(delta: float) -> void:
	_now_s += delta
	if _server == null and _links.is_empty():
		return
	_Accept_Links()
	_Poll_Links()
	_Sweep_Closed()


# ================================================================ 生命周期 / 查询（公开 API）

## 监听（幂等：先 Stop()）。port <= 0 = OS 临时端口（自检用）。
## 失败只 push_warning：端口被占是环境问题，不该让日志出现 ERROR。
func Listen(port: int) -> Error:
	Stop()
	var server := TCPServer.new()
	var err: Error = server.listen(port, BIND_ADDRESS)
	if err != OK:
		push_warning("[WsCmd] listen(port=%d) 失败：%s" % [port, error_string(err)])
		return err
	_server = server
	_listen_port = server.get_local_port()
	print("[WsCmd] listening on %s:%d" % [BIND_ADDRESS, _listen_port])
	return OK


## 全停：关全部连接 + 关监听（幂等；`_exit_tree` 调用）。
func Stop() -> void:
	for link: Dictionary in _links:
		_Close_Link(link, "server stopped")
	_links.clear()
	if _server != null:
		_server.stop()
		_server = null
	if _listen_port > 0:
		print("[WsCmd] stopped (was port %d)" % _listen_port)
	_listen_port = 0


## 0 = 未监听。
func GetListenPort() -> int:
	return _listen_port


func GetBindAddress() -> String:
	return BIND_ADDRESS


func IsListening() -> bool:
	return _server != null and _listen_port > 0


func GetLinkCount() -> int:
	return _links.size()


## 诊断快照（自检 / 驱动用；只读）。
func GetStats() -> Dictionary:
	var subs: Array = []
	for link: Dictionary in _links:
		subs.append({
			"id": int(link.get("id", 0)),
			"events": (link.get("events", []) as Array).duplicate(),
			"pose_hz": float(link.get("pose_hz", DEFAULT_POSE_HZ)),
			"targets": (link.get("targets", []) as Array).duplicate(),
			"closed": bool(link.get("closed", false)),
		})
	return {
		"listening": IsListening(),
		"port": _listen_port,
		"bind": BIND_ADDRESS,
		"clients": _links.size(),
		"subscriptions": subs,
	}


# ================================================================ 连接管理

func _Accept_Links() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var tcp: StreamPeerTCP = _server.take_connection()
		if tcp == null:
			continue
		var peer := WebSocketPeer.new()
		# 必须在 accept_stream() 之前设（连上后再改对已分配的收发缓冲无效）。
		peer.inbound_buffer_size = LINK_BUFFER_BYTES
		peer.outbound_buffer_size = LINK_BUFFER_BYTES
		tcp.set_no_delay(true)
		var err: Error = peer.accept_stream(tcp)
		if err != OK:
			push_warning("[WsCmd] accept_stream 失败：%s" % error_string(err))
			continue
		_links.append({
			"peer": peer,
			"id": _next_link_id,
			"closed": false,
			"events": DEFAULT_EVENTS.duplicate(),
			"pose_hz": DEFAULT_POSE_HZ,
			"targets": [],
			"target_vids": [],
			"last_pose_s": {},
			"last_map_s": -1e18,
		})
		print("[WsCmd] client #%d connected (links=%d)" % [_next_link_id, _links.size()])
		_next_link_id += 1


## 每连接每帧一次 poll：先抽包（OPEN/CLOSING 都抽，先关后抽会丢最后几帧），再看 CLOSED。
func _Poll_Links() -> void:
	for link: Dictionary in _links:
		if bool(link.get("closed", false)):
			continue
		var peer: WebSocketPeer = link.get("peer")
		if peer == null:
			link["closed"] = true
			continue
		peer.poll()
		var state: WebSocketPeer.State = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CLOSING:
			while peer.get_available_packet_count() > 0:
				var bytes: PackedByteArray = peer.get_packet()
				var was_string: bool = peer.was_string_packet()
				_On_Packet(link, bytes, was_string)
		if state == WebSocketPeer.STATE_CLOSED:
			link["closed"] = true


func _Sweep_Closed() -> void:
	if _links.is_empty():
		return
	var keep: Array = []
	for link: Dictionary in _links:
		if bool(link.get("closed", false)):
			print("[WsCmd] client #%d closed (links=%d)" % [int(link.get("id", 0)), keep.size()])
			continue
		keep.append(link)
	_links = keep


func _Close_Link(link: Dictionary, reason: String) -> void:
	var peer: WebSocketPeer = link.get("peer")
	link["closed"] = true
	if peer == null:
		return
	var state: WebSocketPeer.State = peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CLOSING:
		peer.close(WS_CLOSE_GOING_AWAY, reason)


# ================================================================ 下行（Python → Pictor）

func _On_Packet(link: Dictionary, bytes: PackedByteArray, was_string: bool) -> void:
	if not was_string:
		_Send_Ack(link, 0, false, "binary frames not supported")
		return
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		_Send_Ack(link, 0, false, "bad json")     # 不断连（判据 5）
		return
	var obj: Variant = json.data
	if not (obj is Dictionary):
		_Send_Ack(link, 0, false, "bad json")
		return
	_Handle_Command(link, obj)


func _Handle_Command(link: Dictionary, obj: Dictionary) -> void:
	var req_id := int(obj.get("id", 0))
	var cmd := str(obj.get("cmd", ""))
	match cmd:
		"vehicles":
			_Send_Ack(link, req_id, true)
			_Send_Json(link, {"event": "vehicles", "list": _Vehicle_List()})
		"task_set":
			_Handle_Task_Set(link, req_id, obj)
		"mode":
			_Handle_Mode(link, req_id, obj)
		"manual":
			_Handle_Manual(link, req_id, obj)
		"subscribe":
			_Handle_Subscribe(link, req_id, obj)
		_:
			_Send_Ack(link, req_id, false, "unknown cmd: %s" % cmd)


## `task_set`：**先全部解析成功再发**（原子）。每辆车一帧，missions 交给
## `MessageBuilder.build_task_set` → `Encode_Task_Set`（按 type 变长，未知 type 直接不发帧）。
## 本函数是**命令入口门控**：type ∉ {0,2,3} → `ok:false`；type=3 必须带有限且 > 0 的 `half_side`
## → 否则 `ok:false` 且**一帧都不发**（`Encode` 的 printerr 不出现在 ack 里，外部脚本看不到）。
func _Handle_Task_Set(link: Dictionary, req_id: int, obj: Dictionary) -> void:
	var targets := _String_Array(obj.get("targets", []))
	if targets.is_empty():
		_Send_Ack(link, req_id, false, "targets 不能为空")
		return
	var raw_missions: Variant = obj.get("missions", null)
	if not (raw_missions is Array):
		_Send_Ack(link, req_id, false, "missions 必须是数组")
		return
	var missions: Array = []
	for item: Variant in raw_missions:
		if not (item is Dictionary):
			_Send_Ack(link, req_id, false, "missions 元素必须是对象")
			return
		var mx: Variant = item.get("x", null)
		var my: Variant = item.get("y", null)
		if not ((mx is float) or (mx is int)) or not ((my is float) or (my is int)):
			_Send_Ack(link, req_id, false, "mission 缺少数值 x/y")
			return
		# type 门控（task_41 §3.2）：{0 Goto, 2 Follow, 3 Containment} 之外**整帧不发**
		var mt: Variant = item.get("type", ProtocolDef.MISSION_TYPE_GOTO)
		var mty: int = ProtocolDef.Mission_Type_From(mt) if (mt is String) else int(mt)
		if mty != ProtocolDef.MISSION_TYPE_GOTO \
				and mty != ProtocolDef.MISSION_TYPE_FOLLOW \
				and mty != ProtocolDef.MISSION_TYPE_CONTAINMENT:
			_Send_Ack(link, req_id, false, "unsupported mission type: %d" % mty)
			return                                  # 一帧都不发
		var one := {"type": mty, "x": float(mx), "y": float(my)}
		if mty == ProtocolDef.MISSION_TYPE_CONTAINMENT:
			# half_side：必须有限且 > 0（车端 `decode_task_set` 对非法值整帧拒）
			var mh: Variant = item.get("half_side", null)
			if not ((mh is float) or (mh is int)) or not is_finite(float(mh)) or float(mh) <= 0.0:
				_Send_Ack(link, req_id, false, "bad half_side")
				return                              # 一帧都不发
			one["half_side"] = float(mh)
		missions.append(one)
	var vids: Array[String] = []
	for token: String in targets:
		var vid := _Resolve_Target(token)
		if vid.is_empty():
			_Send_Ack(link, req_id, false, "unknown vehicle: %s" % token)
			return              # 一帧都不发
		vids.append(vid)
	for vid: String in vids:
		EventBus.cmd_send.emit([vid] as Array[String], MessageBuilder.build_task_set(missions))
	_Send_Ack(link, req_id, true)


## `mode`：to ∈ {auto, manual}，每车一帧 **msgid 8**（`MODE_MANUAL` / `MODE_AUTO`，1 B；task_44 §1.2 #4）。
func _Handle_Mode(link: Dictionary, req_id: int, obj: Dictionary) -> void:
	var to := str(obj.get("to", "")).strip_edges().to_lower()
	if to != "auto" and to != "manual":
		_Send_Ack(link, req_id, false, "unknown mode: %s" % to)
		return
	var targets := _String_Array(obj.get("targets", []))
	if targets.is_empty():
		_Send_Ack(link, req_id, false, "targets 不能为空")
		return
	var vids: Array[String] = []
	for token: String in targets:
		var vid := _Resolve_Target(token)
		if vid.is_empty():
			_Send_Ack(link, req_id, false, "unknown vehicle: %s" % token)
			return
		vids.append(vid)
	var cmd := MessageBuilder.build_mode_switch_auto() if to == "auto" \
		else MessageBuilder.build_mode_switch_manual()
	for vid: String in vids:
		EventBus.cmd_send.emit([vid] as Array[String], cmd)
	_Send_Ack(link, req_id, true)


## `manual`：两轴连续量手动帧（task_44 Step 3，8 B 运动 payload）。
## `v` / `omega` 必须是有限数值，且 `|v| <= MANUAL_V_MAX`、`|omega| <= MANUAL_OMEGA_MAX`
## （§1.2 #11 定值，**不做**比例换算）——越界 `ok:false` 且**一帧都不发**。
## `v = omega = 0` 合法（= 停车帧）。本入口给 `pictor_ws_ctl.py manual` 用，手动链才有脚本化验证手段。
func _Handle_Manual(link: Dictionary, req_id: int, obj: Dictionary) -> void:
	var raw_v: Variant = obj.get("v", null)
	var raw_w: Variant = obj.get("omega", null)
	if not ((raw_v is float) or (raw_v is int)) or not ((raw_w is float) or (raw_w is int)):
		_Send_Ack(link, req_id, false, "manual 缺少数值 v/omega")
		return
	var fv := float(raw_v)
	var fw := float(raw_w)
	if not is_finite(fv) or not is_finite(fw):
		_Send_Ack(link, req_id, false, "v/omega 必须是有限数值")
		return
	if absf(fv) > ProtocolDef.MANUAL_V_MAX + 1e-6:
		_Send_Ack(link, req_id, false, "v 越界：|v| <= %f（收到 %f）" % [ProtocolDef.MANUAL_V_MAX, fv])
		return                          # 一帧都不发
	if absf(fw) > ProtocolDef.MANUAL_OMEGA_MAX + 1e-6:
		_Send_Ack(link, req_id, false,
				"omega 越界：|omega| <= %f（收到 %f）" % [ProtocolDef.MANUAL_OMEGA_MAX, fw])
		return                          # 一帧都不发
	var targets := _String_Array(obj.get("targets", []))
	if targets.is_empty():
		_Send_Ack(link, req_id, false, "targets 不能为空")
		return
	var vids: Array[String] = []
	for token: String in targets:
		var vid := _Resolve_Target(token)
		if vid.is_empty():
			_Send_Ack(link, req_id, false, "unknown vehicle: %s" % token)
			return                      # 一帧都不发
		vids.append(vid)
	var cmd := MessageBuilder.build_manual_motion(fv, fw)
	for vid: String in vids:
		EventBus.cmd_send.emit([vid] as Array[String], cmd)
	_Send_Ack(link, req_id, true)


## `subscribe`：原子替换本连接订阅；未知名/非法值 → `ok:false` 且**不生效**。
## `pose_hz <= 0` = 不限频（钳到 MAX_POSE_HZ）；`targets = []` = 全部。
func _Handle_Subscribe(link: Dictionary, req_id: int, obj: Dictionary) -> void:
	var events := _String_Array(obj.get("events", link.get("events", [])))
	for ev: String in events:
		if not KNOWN_EVENTS.has(ev):
			_Send_Ack(link, req_id, false, "unknown event: %s" % ev)
			return
	var pose_hz := float(obj.get("pose_hz", link.get("pose_hz", DEFAULT_POSE_HZ)))
	if pose_hz <= 0.0:
		pose_hz = MAX_POSE_HZ
	pose_hz = minf(pose_hz, MAX_POSE_HZ)
	var targets := _String_Array(obj.get("targets", link.get("targets", [])))
	var target_vids: Array[String] = []
	for token: String in targets:
		var vid := _Resolve_Target(token)
		if not vid.is_empty():
			target_vids.append(vid)     # 解析不到的名字留空，靠名字比对兜后续注册
	link["events"] = events
	link["pose_hz"] = pose_hz
	link["targets"] = targets
	link["target_vids"] = target_vids
	link["last_pose_s"] = {}
	_Send_Ack(link, req_id, true, "", {
		"applied": {
			"events": events,
			"pose_hz": pose_hz,
			"targets": targets,
			"targets_resolved": target_vids,
		},
	})


# ================================================================ 上行（Pictor → Python）

func _On_Pose_Received(vehicle_id: String, pose: Dictionary) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "pose"):
			continue
		if not _Pose_Allowed(link, vehicle_id):
			continue
		var pose_hz: float = float(link.get("pose_hz", DEFAULT_POSE_HZ))
		var last: Dictionary = link.get("last_pose_s", {})
		if pose_hz > 0.0 and _now_s - float(last.get(vehicle_id, -1e18)) + FLOAT_EPS < 1.0 / pose_hz:
			continue
		last[vehicle_id] = _now_s
		link["last_pose_s"] = last
		_Send_Json(link, {
			"event": "pose",
			"vid": vehicle_id,
			"name": _Name_Of(vehicle_id),
			"x": float(pose.get("x", 0.0)),
			"y": float(pose.get("y", 0.0)),
			"yaw": float(pose.get("yaw", 0.0)),
			"valid": 1 if bool(pose.get("valid", false)) else 0,
			"gx": int(pose.get("sub_gx", 0)),
			"gy": int(pose.get("sub_gy", 0)),
			"rtk_fixed": 1 if bool(pose.get("rtk_fixed", false)) else 0,
			"t_ms": int(pose.get("time_boot_ms", 0)),
		})


func _On_Vehicle_Registered(vehicle_id: String) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "peer"):
			continue
		_Send_Json(link, {
			"event": "peer_connected",
			"vid": vehicle_id,
			"name": _Name_Of(vehicle_id),
			"node_type": _Node_Type_Of(vehicle_id),
		})


func _On_Peer_Info_Updated(vehicle_id: String, peer_name: String, node_type: String) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "peer"):
			continue
		_Send_Json(link, {
			"event": "peer_info",
			"vid": vehicle_id,
			"name": peer_name,
			"node_type": node_type,
		})


func _On_Vehicle_Unregistered(vehicle_id: String) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "peer"):
			continue
		_Send_Json(link, {"event": "peer_disconnected", "vid": vehicle_id})


## map_delta：只显式订阅、≤MAP_DELTA_HZ，且**只发计数不发 voxels 本体**（避免火管）。
func _On_Map_Delta_Received(voxels: Array) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "map_delta"):
			continue
		if _now_s - float(link.get("last_map_s", -1e18)) + FLOAT_EPS < 1.0 / MAP_DELTA_HZ:
			continue
		link["last_map_s"] = _now_s
		_Send_Json(link, {"event": "map_delta", "count": voxels.size()})


## map_full：只显式订阅，且只发元数据（`EventBus` 的信号不带尺寸，按协议常量 256×256）。
func _On_Map_Full_Received(vehicle_id: String, chunk_x: int, chunk_y: int, cells: PackedByteArray) -> void:
	if _links.is_empty():
		return
	for link: Dictionary in _links:
		if not _Can_Push(link, "map_full"):
			continue
		_Send_Json(link, {
			"event": "map_full",
			"vid": vehicle_id,
			"chunk_x": chunk_x,
			"chunk_y": chunk_y,
			"width": ProtocolDef.MAP_WIDTH,
			"height": ProtocolDef.MAP_HEIGHT,
			"bytes": cells.size(),
		})


# ================================================================ 订阅过滤 / 发送

## 本连接是否该收该事件集（未连上 / 已关 / 未订阅 → 否）。
func _Can_Push(link: Dictionary, event_name: String) -> bool:
	if bool(link.get("closed", false)):
		return false
	var peer: WebSocketPeer = link.get("peer")
	if peer == null:
		return false
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var events: Array = link.get("events", [])
	return events.has(event_name)


## `targets` 过滤：空 = 全部；否则按 vid 或车名比对（名字未知的 vid 在有 targets 时不推）。
func _Pose_Allowed(link: Dictionary, vehicle_id: String) -> bool:
	var targets: Array = link.get("targets", [])
	if targets.is_empty():
		return true
	var vids: Array = link.get("target_vids", [])
	if vids.has(vehicle_id):
		return true
	var vname := _Name_Of(vehicle_id)
	if vname.is_empty():
		return false
	return targets.has(vname)


func _Send_Ack(link: Dictionary, req_id: int, ok: bool, error := "", extra: Dictionary = {}) -> void:
	var msg := {"ack": req_id, "ok": ok}
	if not ok:
		msg["error"] = error if not error.is_empty() else "failed"
	for key: String in extra:
		msg[key] = extra[key]
	_Send_Json(link, msg)


func _Send_Json(link: Dictionary, msg: Dictionary) -> bool:
	var peer: WebSocketPeer = link.get("peer")
	if peer == null:
		return false
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return peer.send_text(JSON.stringify(msg)) == OK


# ================================================================ 车名 ↔ vid（VehicleRegistry 是唯一数据源）

## 惰性解析 + is_instance_valid 复检（本节点在 main.tscn 里排在 VehicleRegistry **之前**）。
func _Get_Registry() -> Node:
	if _registry != null and is_instance_valid(_registry):
		return _registry
	_registry = get_node_or_null(REGISTRY_PATH)
	if _registry == null and not _registry_warned:
		_registry_warned = true
		push_warning("[WsCmd] 找不到 VehicleRegistry（%s），车名解析不可用" % REGISTRY_PATH)
	return _registry


## 车名或 hex vid → vid；解析不到返回 ""（调用方转成 `ok:false`）。
func _Resolve_Target(token: String) -> String:
	var reg := _Get_Registry()
	if reg == null:
		return ""
	var key := token.strip_edges()
	if key.is_empty():
		return ""
	var table: Dictionary = reg.vehicles
	if table.has(key):
		return key                 # 已接受 hex vid 直填（vehicles 的返回里就有）
	if reg.has_method("get_id_by_name"):
		return str(reg.get_id_by_name(key))
	return ""


## 注册表里的车名（没有 = ""）；只读，不缓存。
func _Name_Of(vehicle_id: String) -> String:
	var reg := _Get_Registry()
	if reg == null:
		return ""
	var table: Dictionary = reg.vehicles
	if not table.has(vehicle_id):
		return ""
	return str((table[vehicle_id] as Dictionary).get("name", ""))


func _Node_Type_Of(vehicle_id: String) -> String:
	var reg := _Get_Registry()
	if reg == null:
		return ""
	var table: Dictionary = reg.vehicles
	if not table.has(vehicle_id):
		return ""
	return str((table[vehicle_id] as Dictionary).get("node_type", ""))


## 已注册车列表（`{name, vid, node_type}`，按 vid 排序保证确定性）。
func _Vehicle_List() -> Array:
	var out: Array = []
	var reg := _Get_Registry()
	if reg == null:
		return out
	var table: Dictionary = reg.vehicles
	var ids: Array = table.keys()
	ids.sort()
	for vid: String in ids:
		var v: Dictionary = table[vid]
		out.append({
			"name": str(v.get("name", "")),
			"vid": vid,
			"node_type": str(v.get("node_type", "")),
		})
	return out


# ================================================================ 命令行参数

## 只认 `--ws-port=N`（也容忍 `--ws-port N`）；非法 → 0（= 关闭），只 push_warning。
static func _Parse_Port(args: PackedStringArray) -> int:
	for i in range(args.size()):
		var arg := args[i]
		if arg.begins_with(ARG_WS_PORT):
			return _Clamp_Port(arg.substr(ARG_WS_PORT.length()))
		if arg == ARG_WS_PORT_BARE and i + 1 < args.size():
			return _Clamp_Port(args[i + 1])
	return 0


static func _Clamp_Port(raw: String) -> int:
	var text := raw.strip_edges()
	if not text.is_valid_int():
		push_warning("[WsCmd] 非法端口 `%s`，WS 命令通道关闭" % text)
		return 0
	var port := text.to_int()
	if port < 1 or port > 65535:
		push_warning("[WsCmd] 端口越界 `%d`（1..65535），WS 命令通道关闭" % port)
		return 0
	return port


func _String_Array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			if item is String or item is StringName:
				var text := str(item).strip_edges()
				if not text.is_empty():
					out.append(text)
	return out
