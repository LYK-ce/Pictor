extends SceneTree
## Present by KeJi
## Date: 2026-06-08
##
## test/websocket_client/test_websocket.gd — headless 测试 WebSocketClient

var _bus: Node = null
var _passed := 0
var _failed := 0

# 捕获变量
var _cap_pose := {}
var _cap_voxels := []
var _cap_is_full := false
var _cap_points := []
var _cap_sent := ""   # 记录 ctrl_send 发出的文本


func _init() -> void:
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)

	_bus.pose_received.connect(func(d: Dictionary): _cap_pose = d)
	_bus.voxel_received.connect(func(v: Array, f: bool): _cap_voxels = v; _cap_is_full = f)
	_bus.path_received.connect(func(p: Array): _cap_points = p)
	_bus.ctrl_send.connect(func(d: Dictionary): _cap_sent = JSON.stringify(d))

	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=".repeat(50))
	print("  WebSocketClient Test Suite")
	print("=".repeat(50))

	_test_pose_message()
	_test_voxel_full_message()
	_test_voxel_delta_message()
	_test_path_message()
	_test_bad_json()
	_test_unknown_type()
	_test_ctrl_send()

	print("\n" + "=".repeat(50))
	if _failed == 0:
		print("  ALL %d TESTS PASSED ✓" % _passed)
	else:
		print("  %d passed, %d FAILED ✗" % [_passed, _failed])
	print("=".repeat(50))
	quit()


func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % msg)
	else:
		_failed += 1
		printerr("  ✗ FAIL: %s" % msg)


func _make_ws() -> Node:
	var ws = load("res://src/websocket_client/websocket_client.gd").new()
	ws.name = "WebSocketClient"
	root.add_child(ws)
	return ws


# ─── Test 1: pose message ────────────────────────────────────

func _test_pose_message() -> void:
	print("\n[1] pose message dispatch")
	var ws := _make_ws()
	_cap_pose = {}

	var json := '{"type":"pose","ts":123.0,"x":1.5,"y":0.0,"z":3.2,"yaw":0.785,"vx":0.5,"vz":0.0}'
	ws._on_message(json)

	_assert(_cap_pose.get("x") == 1.5, "pose x matches")
	_assert(_cap_pose.get("yaw") == 0.785, "pose yaw matches")


# ─── Test 2: voxel_full message ──────────────────────────────

func _test_voxel_full_message() -> void:
	print("\n[2] voxel_full message dispatch")
	var ws := _make_ws()
	_cap_voxels = []
	_cap_is_full = false

	var json := '{"type":"voxel_full","ts":123.0,"voxels":[{"gx":0,"gy":0,"gz":0,"state":1,"conf":0.95},{"gx":1,"gy":0,"gz":0,"state":2,"conf":0.8}]}'
	ws._on_message(json)

	_assert(_cap_voxels.size() == 2, "voxel count = 2")
	_assert(_cap_is_full, "is_full = true")
	_assert(_cap_voxels[0].get("state") == 1, "voxel state = 1")


# ─── Test 3: voxel_delta message ─────────────────────────────

func _test_voxel_delta_message() -> void:
	print("\n[3] voxel_delta message dispatch")
	var ws := _make_ws()
	_cap_voxels = []
	_cap_is_full = true

	var json := '{"type":"voxel_delta","ts":123.0,"voxels":[{"gx":5,"gy":0,"gz":5,"state":2,"conf":0.9}]}'
	ws._on_message(json)

	_assert(_cap_voxels.size() == 1, "voxel count = 1")
	_assert(not _cap_is_full, "is_full = false")


# ─── Test 4: path message ────────────────────────────────────

func _test_path_message() -> void:
	print("\n[4] path message dispatch")
	var ws := _make_ws()
	_cap_points = []

	var json := '{"type":"path","ts":123.0,"points":[{"x":0,"z":0},{"x":1,"z":2},{"x":3,"z":5}]}'
	ws._on_message(json)

	_assert(_cap_points.size() == 3, "point count = 3")
	_assert(_cap_points[2].get("x") == 3, "last point x = 3")


# ─── Test 5: bad JSON ────────────────────────────────────────

func _test_bad_json() -> void:
	print("\n[5] bad JSON handling")
	var ws := _make_ws()
	_cap_pose = {}

	ws._on_message("not json at all")

	_assert(_cap_pose.is_empty(), "no data emitted on bad JSON")


# ─── Test 6: unknown type ────────────────────────────────────

func _test_unknown_type() -> void:
	print("\n[6] unknown type handling")
	var ws := _make_ws()
	_cap_pose = {}
	_cap_voxels = []
	_cap_points = []

	ws._on_message('{"type":"unknown_packet","data":42}')

	_assert(_cap_pose.is_empty(), "pose not emitted")
	_assert(_cap_voxels.is_empty(), "voxels not emitted")
	_assert(_cap_points.is_empty(), "path not emitted")


# ─── Test 7: ctrl_send forwarding ────────────────────────────

func _test_ctrl_send() -> void:
	print("\n[7] ctrl_send → pending queue (disconnected)")
	var ws := _make_ws()
	_cap_sent = ""

	_bus.ctrl_send.emit({"type": "ctrl", "key": "w", "action": "press"})

	# 未连接时消息进入 _pending_messages
	_assert(ws._pending_messages.size() == 1, "pending queue has 1 msg")
	var parsed: Dictionary = JSON.parse_string(ws._pending_messages[0])
	_assert(parsed.get("key") == "w", "pending msg key = w")
