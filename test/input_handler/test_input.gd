extends SceneTree
## Present by KeJi
## Date: 2026-06-08

var _bus: Node = null
var _passed := 0
var _failed := 0
var _cap_cmd := {}
var _emit_count := 0

func _init() -> void:
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)
	_bus.ctrl_send.connect(func(d: Dictionary): _cap_cmd = d; _emit_count += 1)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  InputHandler Test (cmd protocol)")
	print("=".repeat(50))

	_test_make_cmd()
	_test_full_flow()

	print("\n" + "=".repeat(50))
	if _failed == 0: print("  ALL %d TESTS PASSED ✓" % _passed)
	else: print("  %d passed, %d FAILED ✗" % [_passed, _failed])
	print("=".repeat(50))
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)

func _make_handler() -> Node:
	var h: Node = load("res://src/input_handler/input_handler.gd").new()
	h.name = "InputHandler"
	root.add_child(h)
	return h

func _test_make_cmd() -> void:
	print("\n[1] _make_cmd")
	var h := _make_handler()
	var d: Dictionary = h._make_cmd("forward")
	_assert(d.get("cmd") == "forward", "forward")
	d = h._make_cmd("stop")
	_assert(d.get("cmd") == "stop", "stop")

func _test_full_flow() -> void:
	print("\n[2] Full flow: key → cmd → EventBus")
	var h := _make_handler()

	# W press → forward
	var ev := InputEventKey.new()
	ev.keycode = KEY_W; ev.pressed = true; ev.echo = false
	_cap_cmd = {}; _emit_count = 0
	h._input(ev)
	_assert(_emit_count == 1, "W → 1 emit")
	_assert(_cap_cmd.get("cmd") == "forward", "W → forward")

	# W release → stop
	ev.pressed = false
	h._input(ev)
	_assert(_emit_count == 2, "W↑ → 1 more emit")
	_assert(_cap_cmd.get("cmd") == "stop", "W↑ → stop")

	# Space → stop
	ev.keycode = KEY_SPACE; ev.pressed = true
	h._input(ev)
	_assert(_cap_cmd.get("cmd") == "stop", "Space → stop")

	# A → spin_left
	ev.keycode = KEY_A; ev.pressed = true
	h._input(ev)
	_assert(_cap_cmd.get("cmd") == "spin_left", "A → spin_left")

	# D → spin_right
	ev.keycode = KEY_D; ev.pressed = true
	h._input(ev)
	_assert(_cap_cmd.get("cmd") == "spin_right", "D → spin_right")
