extends SceneTree
## test/ui/test_zoom_slider.gd
var _bus: Node = null
var _passed := 0
var _failed := 0
var _zoom_val := 0.0
var _zoom_count := 0

func _init() -> void:
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)
	_bus.zoom_changed.connect(func(z: float): _zoom_val = z; _zoom_count += 1)
	process_frame.connect(_setup, CONNECT_ONE_SHOT)

var _zs: Control = null

func _setup() -> void:
	var s := load("res://src/ui/zoom_slider/zoom_slider.tscn")
	_zs = s.instantiate()
	root.add_child(_zs)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("=".repeat(50))
	print("  ZoomSlider Test")
	print("=".repeat(50))

	_assert(_zs != null, "ZoomSlider instantiated")

	# 滑块拖动 emit
	var slider: VSlider = _zs.get_node("Panel/VSlider")
	slider.value = 2.5
	_zoom_count = 0
	slider.value_changed.emit(2.5)
	_assert(_zoom_count >= 1, "slider → EventBus emit")
	_assert(is_equal_approx(_zoom_val, 2.5), "zoom = 2.5")

	# Renderer 发出初始值 → 滑块同步
	_bus.zoom_changed.emit(1.0)
	_assert(is_equal_approx(slider.value, 1.0), "slider synced to 1.0")

	if _failed == 0: print("\n  ALL %d TESTS PASSED ✓" % _passed)
	else: print("\n  %d passed, %d FAILED ✗" % [_passed, _failed])
	quit()

func _assert(c: bool, m: String) -> void:
	if c: _passed += 1; print("  ✓ %s" % m)
	else: _failed += 1; printerr("  ✗ FAIL: %s" % m)
