extends SceneTree
## test/renderer_3d/test_path_line.gd
var _passed := 0
var _failed := 0

func _init() -> void: process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  PathLine3D Test")
	print("=".repeat(50))
	var s := load("res://src/renderer_3d/path_line_3d.tscn")
	var p: Node3D = s.instantiate()
	root.add_child(p)
	await process_frame

	p.set_points([{"x":0,"y":0,"z":0},{"x":1,"y":2,"z":3}])
	_assert(p.get_child_count() >= 1, "MeshInstance3D child created")

	p.set_points([])
	await process_frame
	_assert(p.get_child_count() == 0, "empty clears children")

	if _failed == 0: print("\n  ALL %d TESTS PASSED ✓" % _passed)
	else: print("\n  %d passed, %d FAILED ✗" % [_passed, _failed])
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
