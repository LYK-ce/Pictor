extends SceneTree
## test/renderer_3d/test_vehicle_marker.gd
var _passed := 0
var _failed := 0

func _init() -> void: process_frame.connect(_setup, CONNECT_ONE_SHOT)
var _v: Node3D = null

func _setup() -> void:
	var s := load("res://src/renderer_3d/vehicle_marker_3d.tscn")
	_v = s.instantiate()
	root.add_child(_v)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  VehicleMarker3D Test")
	print("=".repeat(50))
	_v.update_pose(1.5, 2.0, 3.2, 0.785)
	_assert(is_equal_approx(_v.position.x, 1.5*16), "pos.x = 24")
	_assert(is_equal_approx(_v.position.y, 2.0*16), "pos.y = 32")
	_assert(is_equal_approx(_v.position.z, 3.2*16), "pos.z = 51.2")
	_assert(is_equal_approx(_v.rotation.y, 0.785), "yaw = 0.785")
	if _failed == 0: print("\n  ALL %d TESTS PASSED ✓" % _passed)
	else: print("\n  %d passed, %d FAILED ✗" % [_passed, _failed])
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
