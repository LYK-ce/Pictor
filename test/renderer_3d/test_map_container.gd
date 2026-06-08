extends SceneTree
## test/renderer_3d/test_map_container.gd
var _passed := 0
var _failed := 0

func _init() -> void: process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  MapContainer3D Test")
	print("=".repeat(50))

	var s := load("res://src/renderer_3d/map_container_3d.tscn")
	var m: Node3D = s.instantiate()
	root.add_child(m)

	# set_cell → get_cell
	m.set_cell(0, 0, 0, {"state": 2, "conf": 0.9})
	var d: Dictionary = m.get_cell(0, 0, 0)
	_assert(d.get("state") == 2, "state=2")
	_assert(d.get("conf") == 0.9, "conf=0.9")

	# set_full
	m.set_full([{"gx":1,"gy":0,"gz":1,"state":2,"conf":1.0},{"gx":2,"gy":1,"gz":2,"state":2,"conf":0.5}])
	var cells: Array = m.get_all_cells()
	_assert(cells.size() == 2, "2 cells after full")

	# set_delta
	m.set_delta([{"gx":3,"gy":0,"gz":3,"state":2,"conf":0.8}])
	cells = m.get_all_cells()
	_assert(cells.size() == 3, "3 cells after delta")

	print("\n" + "=".repeat(50))
	if _failed == 0: print("  ALL %d TESTS PASSED ✓" % _passed)
	else: print("  %d passed, %d FAILED ✗" % [_passed, _failed])
	print("=".repeat(50))
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
