extends SceneTree
## Present by KeJi
## Date: 2026-06-08

var _passed := 0
var _failed := 0

func _init() -> void:
	process_frame.connect(_setup, CONNECT_ONE_SHOT)

var _v: Node2D = null

func _setup() -> void:
	var s := load("res://src/renderer_2d/vehicle_marker_2d.tscn")
	_v = s.instantiate()
	root.add_child(_v)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  VehicleMarker2D Test")
	print("=".repeat(50))

	_v.update_pose(1.5, 3.2, 0.785)
	_assert(is_equal_approx(_v.position.x, 1.5), "position.x = 1.5")
	_assert(is_equal_approx(_v.position.y, 3.2), "position.y = 3.2")
	_assert(is_equal_approx(_v.rotation, 0.785), "rotation = 0.785")

	# Test 2: Camera2D exists
	var cam: Camera2D = _v.get_node("Camera2D")
	_assert(cam != null, "Camera2D child exists")
	_assert(cam.enabled, "Camera2D enabled")

	print("\n" + "=".repeat(50))
	if _failed == 0: print("  ALL %d TESTS PASSED ✓" % _passed)
	else: print("  %d passed, %d FAILED ✗" % [_passed, _failed])
	print("=".repeat(50))
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
