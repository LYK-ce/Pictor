extends SceneTree
## Present by KeJi
## Date: 2026-06-08

var _passed := 0
var _failed := 0

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  PathLine2D Test")
	print("=".repeat(50))

	var s := load("res://src/renderer_2d/path_line_2d.tscn")
	var p: Node2D = s.instantiate()
	root.add_child(p)

	# Test 1: set_points
	p.set_points([{"x":0,"z":0},{"x":1,"z":1},{"x":2,"z":3}])
	var line: Line2D = p.get_node("Line2D")
	_assert(line.points.size() == 3, "3 points")
	_assert(line.points[2].x == 2.0, "last x = 2")

	# Test 2: empty path
	p.set_points([])
	_assert(line.points.size() == 0, "empty path OK")

	print("\n" + "=".repeat(50))
	if _failed == 0: print("  ALL %d TESTS PASSED ✓" % _passed)
	else: print("  %d passed, %d FAILED ✗" % [_passed, _failed])
	print("=".repeat(50))
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
