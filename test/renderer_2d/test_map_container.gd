extends SceneTree
## Present by KeJi
## Date: 2026-06-08
##
## test/renderer_2d/test_map_container.gd

var _passed := 0
var _failed := 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=".repeat(50))
	print("  MapContainer2D Test Suite")
	print("=".repeat(50))

	_test_set_get_cell()
	_test_set_full()
	_test_set_delta()
	_test_world_to_tile()
	_test_get_all_cells()

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


func _make_map() -> Node2D:
	var s := load("res://src/renderer_2d/map_container_2d.tscn")
	var m: Node2D = s.instantiate()
	root.add_child(m)
	return m


# ─── Test 1: set_cell → get_cell ─────────────────────────────

func _test_set_get_cell() -> void:
	print("\n[1] set_cell → get_cell")
	var m := _make_map()

	m.set_cell(5, 10, {"state": 2, "conf": 0.85, "ts": 123.0, "source": "lidar"})
	var d: Dictionary = m.get_cell(5, 10)

	_assert(d.get("state") == 2, "state = 2")
	_assert(d.get("conf") == 0.85, "conf = 0.85")
	_assert(d.get("ts") == 123.0, "ts = 123")
	_assert(d.get("source") == "lidar", "source = lidar")


# ─── Test 2: set_full covers old ─────────────────────────────

func _test_set_full() -> void:
	print("\n[2] set_full replaces old data")
	var m := _make_map()

	# write old
	m.set_cell(0, 0, {"state": 1, "conf": 1.0})
	# full overwrite
	m.set_full([
		{"gx": 1, "gz": 1, "state": 2, "conf": 0.9},
		{"gx": 2, "gz": 2, "state": 2, "conf": 0.8},
	])

	var cells: Array = m.get_all_cells()
	_assert(cells.size() == 2, "only 2 cells after full")
	_assert(m.get_cell(0, 0).get("state") == 0, "old cell cleared")


# ─── Test 3: set_delta adds ──────────────────────────────────

func _test_set_delta() -> void:
	print("\n[3] set_delta adds to existing")
	var m := _make_map()

	m.set_full([
		{"gx": 0, "gz": 0, "state": 1, "conf": 1.0},
	])
	m.set_delta([
		{"gx": 1, "gz": 1, "state": 2, "conf": 0.5},
	])

	var cells: Array = m.get_all_cells()
	_assert(cells.size() == 2, "delta adds → 2 cells")
	_assert(m.get_cell(0, 0).get("state") == 1, "original kept")
	_assert(m.get_cell(1, 1).get("state") == 2, "delta added")


# ─── Test 4: world_to_tile ───────────────────────────────────

func _test_world_to_tile() -> void:
	print("\n[4] world_to_tile conversion")
	var m := _make_map()

	var t: Vector2i = m.world_to_tile(1.23, 4.56)
	_assert(t.x == 12, "1.23 / 0.1 = 12")
	_assert(t.y == 45, "4.56 / 0.1 = 45")


# ─── Test 5: get_all_cells ───────────────────────────────────

func _test_get_all_cells() -> void:
	print("\n[5] get_all_cells")
	var m := _make_map()

	for i in range(10):
		m.set_cell(i, i, {"state": 2, "conf": 1.0})

	var cells: Array = m.get_all_cells()
	_assert(cells.size() == 10, "10 cells written → 10 returned")
