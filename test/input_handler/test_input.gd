extends SceneTree
## Present by KeJi
## Date: 2026-06-08
##
## test/input_handler/test_input.gd — headless 测试 InputHandler

var _bus: Node = null
var _passed := 0
var _failed := 0

var _cap_ctrl := {}
var _emit_count := 0


func _init() -> void:
	# 手动建立 EventBus（--script 不加载 Autoload）
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)
	_bus.ctrl_send.connect(_on_ctrl_send)

	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=".repeat(50))
	print("  InputHandler Test Suite")
	print("=".repeat(50))

	_test_make_ctrl()
	_test_press_release()
	_test_key_map()
	_test_echo_filter()
	_test_non_target_key()
	_test_full_flow()

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


func _on_ctrl_send(ctrl: Dictionary) -> void:
	_cap_ctrl = ctrl
	_emit_count += 1


func _make_handler() -> Node:
	var h = load("res://src/input_handler/input_handler.gd").new()
	h.name = "InputHandler"
	root.add_child(h)
	return h


# ─── Test 1: _make_ctrl basic ────────────────────────────────

func _test_make_ctrl() -> void:
	print("\n[1] _make_ctrl format")
	var handler := _make_handler()

	var ctrl: Dictionary = handler._make_ctrl("w", true)
	_assert(ctrl.get("type") == "ctrl", "type = ctrl")
	_assert(ctrl.get("key") == "w", "key = w")
	_assert(ctrl.get("action") == "press", "action = press")


# ─── Test 2: press vs release ────────────────────────────────

func _test_press_release() -> void:
	print("\n[2] Press vs release")
	var handler := _make_handler()

	var press: Dictionary = handler._make_ctrl("s", true)
	var release: Dictionary = handler._make_ctrl("s", false)

	_assert(press.get("action") == "press", "pressed → press")
	_assert(release.get("action") == "release", "released → release")


# ─── Test 3: all mapped keys ─────────────────────────────────

func _test_key_map() -> void:
	print("\n[3] All mapped keys")
	var handler := _make_handler()

	var keys := ["w", "s", "a", "d", "space"]
	for k in keys:
		var ctrl: Dictionary = handler._make_ctrl(k, true)
		_assert(ctrl.get("key") == k, "key = %s" % k)


# ─── Test 4: echo filter ─────────────────────────────────────

func _test_echo_filter() -> void:
	print("\n[4] Echo filter")
	var handler := _make_handler()

	# 用 InputEventKey echo=true 模拟，_input 应跳过
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.pressed = true
	ev.echo = true

	_cap_ctrl = {}
	_emit_count = 0
	handler._input(ev)

	_assert(_emit_count == 0, "echo event ignored")


# ─── Test 5: non-target key ──────────────────────────────────

func _test_non_target_key() -> void:
	print("\n[5] Non-target key ignored")
	var handler := _make_handler()

	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	ev.echo = false

	_cap_ctrl = {}
	_emit_count = 0
	handler._input(ev)

	_assert(_emit_count == 0, "ENTER ignored")


# ─── Test 6: full flow via _input ────────────────────────────

func _test_full_flow() -> void:
	print("\n[6] Full flow: _input → EventBus")
	var handler := _make_handler()

	# W press
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.pressed = true
	ev.echo = false

	_cap_ctrl = {}
	_emit_count = 0
	handler._input(ev)

	_assert(_emit_count == 1, "W press → 1 emit")
	_assert(_cap_ctrl.get("key") == "w", "key match")
	_assert(_cap_ctrl.get("action") == "press", "action match")

	# W release
	ev.pressed = false
	handler._input(ev)

	_assert(_emit_count == 2, "W release → 2 emits")
	_assert(_cap_ctrl.get("action") == "release", "release action match")

	# Space press (estop)
	ev.keycode = KEY_SPACE
	ev.pressed = true
	handler._input(ev)

	_assert(_emit_count == 3, "Space → 3 emits")
	_assert(_cap_ctrl.get("key") == "space", "estop key match")
