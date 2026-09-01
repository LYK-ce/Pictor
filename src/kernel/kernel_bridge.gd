extends Node
## Presented by KeJi
## Date ： 2026-09-01
##
## KernelBridge — Rust 桥（PleiadesKernel）与 EventBus 的适配器
## 上行：robot_frame → parse_orion_frame → EventBus（pose/map）；peer_* → registered/unregistered/name
## 下行：EventBus.cmd_send → OrionMessages.Build_Cmd → kernel.send_command
## peer_discovered / peer_left 不消费（决策 #6/#7，mDNS 发现态不建面板）

var kernel: Object = null


func _ready() -> void:
	if not ClassDB.class_exists("PleiadesKernel"):
		printerr("[KernelBridge] PleiadesKernel 类未注册（.gdextension 未加载）")
		return
	kernel = ClassDB.instantiate("PleiadesKernel")
	kernel.robot_frame.connect(_on_robot_frame)
	kernel.peer_connected.connect(_on_peer_connected)
	kernel.peer_disconnected.connect(_on_peer_disconnected)
	kernel.peer_info_updated.connect(_on_peer_info_updated)
	add_child(kernel)  # 触发 Rust 侧 ready() → 后台 bootstrap
	EventBus.cmd_send.connect(_on_cmd_send)


func _process(_delta: float) -> void:
	if kernel:
		kernel.poll()


## 上行：原始 ORION 帧 → 解析 → 按 msgid + sysid 分发
func _on_robot_frame(data: PackedByteArray) -> void:
	var r := MessageParser.parse_orion_frame(data)
	if not r.ok:
		printerr("[KernelBridge] parse_orion_frame failed: ", r.error)
		return
	var sysid: PackedByteArray = r.get("sysid", PackedByteArray())
	if sysid.is_empty():
		printerr("[KernelBridge] empty sysid, drop msgid=", r.msgid)
		return
	var vid := sysid.hex_encode()
	match r.msgid:
		ProtocolDef.MSGID_POSE:
			EventBus.pose_received.emit(vid, r.data)
		ProtocolDef.MSGID_MAP_FULL:
			var d: Dictionary = r.data
			EventBus.map_full_received.emit(vid, d.get("chunk_x", 0), d.get("chunk_y", 0), d.get("cells", PackedByteArray()))
		ProtocolDef.MSGID_MAP_DELTA:
			EventBus.map_delta_received.emit(r.data.get("voxels", []))
		_:
			# MANUAL_CONTROL / TASK_SET 为下行消息，不从车上行，忽略
			pass


## 下行：cmd_send → 拼帧 → 逐车 send_command
func _on_cmd_send(targets: Array[String], cmd: Dictionary) -> void:
	if not kernel:
		printerr("[KernelBridge] kernel 未就绪，cmd 丢弃: ", cmd)
		return
	# TASK_SET 群发：按 targets 填 members（vehicle_id 即 hex peer_id，直接 hex_decode）
	if cmd.get("msgid", -1) == ProtocolDef.MSGID_TASK_SET and not cmd.has("members"):
		var members: Array = []
		if not cmd.get("missions", []).is_empty():
			for id in targets:
				members.append(id.hex_decode())
		cmd["members"] = members
	var frame := OrionMessages.Build_Cmd(cmd)
	if frame.is_empty():
		printerr("[KernelBridge] cmd encode failed: ", cmd)
		return
	for id in targets:
		kernel.send_command(id, frame)


## peer 事件 → 车辆生命周期
func _on_peer_connected(peer_id: String) -> void:
	EventBus.vehicle_registered.emit(peer_id)


func _on_peer_disconnected(peer_id: String) -> void:
	EventBus.vehicle_unregistered.emit(peer_id)


func _on_peer_info_updated(peer_id: String, peer_name: String, node_type: String) -> void:
	if peer_name.is_empty():
		return  # 空名过滤（models/sessions 也会发 peer_info_updated）
	EventBus.peer_info_updated.emit(peer_id, peer_name, node_type)
