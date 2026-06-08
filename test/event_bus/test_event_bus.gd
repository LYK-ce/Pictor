extends SceneTree
## Present by KeJi
## Date: 2026-06-08
##
## test/event_bus/test_event_bus.gd — headless 测试 EventBus 信号
##
## 注意：--script 模式不加载 Autoload，需手动实例化 EventBus。
## GDScript 2.0 中 lambda 捕获局部变量不可作为 signal 回调，使用成员函数。

var _bus: Node = null
var _passed := 0
var _failed := 0

# 测试捕获变量（替代 lambda 闭包）
var _cap_received := false
var _cap_pose := {}
var _cap_voxels := []
var _cap_is_full := false
var _cap_ctrl := {}
var _cap_count_a := 0
var _cap_count_b := 0


func _init() -> void:
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=".repeat(50))
	print("  EventBus Test Suite")
	print("=".repeat(50))

	_test_send_receive()
	_test_pose_received()
	_test_voxel_received()
	_test_ctrl_send()
	_test_multi_subscriber()

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


# ─── Signal callbacks ────────────────────────────────────────

func _cb_send_receive(_d: Dictionary) -> void:
	_cap_received = true

func _cb_pose(pose: Dictionary) -> void:
	_cap_pose = pose

func _cb_voxel(voxels: Array, is_full: bool) -> void:
	_cap_voxels = voxels
	_cap_is_full = is_full

func _cb_ctrl(ctrl: Dictionary) -> void:
	_cap_ctrl = ctrl

func _cb_multi_a(_d: Dictionary) -> void:
	_cap_count_a += 1

func _cb_multi_b(_d: Dictionary) -> void:
	_cap_count_b += 1


# ─── Test 1: basic send/receive ──────────────────────────────

func _test_send_receive() -> void:
	print("\n[1] Signal send & receive")
	_cap_received = false

	_bus.pose_received.connect(_cb_send_receive)
	_bus.pose_received.emit({"x": 0.0})
	_bus.pose_received.disconnect(_cb_send_receive)

	_assert(_cap_received, "emit → callback invoked")


# ─── Test 2: pose_received data integrity ────────────────────

func _test_pose_received() -> void:
	print("\n[2] pose_received data integrity")
	_cap_pose = {}

	_bus.pose_received.connect(_cb_pose)
	_bus.pose_received.emit({"ts": 123.0, "x": 1.5, "y": 0.0, "z": 3.2, "yaw": 0.785, "vx": 0.5, "vz": 0.0})
	_bus.pose_received.disconnect(_cb_pose)

	_assert(_cap_pose.get("ts") == 123.0, "ts matches")
	_assert(_cap_pose.get("x") == 1.5, "x matches")
	_assert(_cap_pose.get("yaw") == 0.785, "yaw matches")


# ─── Test 3: voxel_received params ───────────────────────────

func _test_voxel_received() -> void:
	print("\n[3] voxel_received params")
	_cap_voxels = []
	_cap_is_full = false

	_bus.voxel_received.connect(_cb_voxel)

	var test_data := [
		{"gx": 0, "gy": 0, "gz": 0, "state": 1, "conf": 0.95},
		{"gx": 1, "gy": 0, "gz": 0, "state": 2, "conf": 0.80},
	]
	_bus.voxel_received.emit(test_data, true)
	_bus.voxel_received.disconnect(_cb_voxel)

	_assert(_cap_voxels.size() == 2, "voxel count matches")
	_assert(_cap_is_full, "is_full = true")
	_assert(_cap_voxels[0].get("state") == 1, "voxel state matches")


# ─── Test 4: ctrl_send data integrity ────────────────────────

func _test_ctrl_send() -> void:
	print("\n[4] ctrl_send data integrity")
	_cap_ctrl = {}

	_bus.ctrl_send.connect(_cb_ctrl)
	_bus.ctrl_send.emit({"type": "ctrl", "key": "w", "action": "press"})
	_bus.ctrl_send.disconnect(_cb_ctrl)

	_assert(_cap_ctrl.get("key") == "w", "key = w")
	_assert(_cap_ctrl.get("action") == "press", "action = press")


# ─── Test 5: multiple subscribers ────────────────────────────

func _test_multi_subscriber() -> void:
	print("\n[5] Multiple subscribers")
	_cap_count_a = 0
	_cap_count_b = 0

	_bus.pose_received.connect(_cb_multi_a)
	_bus.pose_received.connect(_cb_multi_b)
	_bus.pose_received.emit({"x": 0.0})
	_bus.pose_received.disconnect(_cb_multi_a)
	_bus.pose_received.disconnect(_cb_multi_b)

	_assert(_cap_count_a == 1, "subscriber A called")
	_assert(_cap_count_b == 1, "subscriber B called")
