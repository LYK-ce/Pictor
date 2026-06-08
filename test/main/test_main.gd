extends SceneTree
## Present by KeJi
## Date: 2026-06-08
##
## test/main/test_main.gd — 集成测试 Main 场景

var _bus: Node = null
var _passed := 0
var _failed := 0

var _cap_pose := {}
var _cap_voxels := []
var _cap_path_points := []
var _cap_ctrl := {}
var _pose_count := 0


func _init() -> void:
	_bus = load("res://src/event_bus/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)

	_bus.pose_received.connect(_on_pose)
	_bus.voxel_received.connect(_on_voxel)
	_bus.path_received.connect(_on_path)
	_bus.ctrl_send.connect(_on_ctrl)

	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("=".repeat(50))
	print("  Main Scene Integration Test")
	print("=".repeat(50))

	# 加载 Main 场景
	var main_scene := load("res://src/main/main.tscn")
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame  # 让 _ready 执行
	await process_frame  # 再等一帧让 WS 开始连接

	# 检查子组件
	var has_ws: bool = main.has_node("WebSocketClient")
	var has_ih: bool = main.has_node("InputHandler")
	_assert(has_ws, "WebSocketClient instantiated")
	_assert(has_ih, "InputHandler instantiated")
	print("  children: ", main.get_child_count())

	# 模拟按键：W 前进
	var ev_w := InputEventKey.new()
	ev_w.keycode = KEY_W
	ev_w.pressed = true
	ev_w.echo = false
	Input.parse_input_event(ev_w)

	# 模拟按键：Space 急停
	var ev_space := InputEventKey.new()
	ev_space.keycode = KEY_SPACE
	ev_space.pressed = true
	ev_space.echo = false
	Input.parse_input_event(ev_space)

	# 等几帧让消息流通
	for _i in range(30):
		await process_frame

	# 验证 voxel_full
	_assert(_cap_voxels.size() > 0, "voxel_full received: %d cells" % _cap_voxels.size())

	# 验证 path
	_assert(_cap_path_points.size() > 0, "path received: %d points" % _cap_path_points.size())

	# 验证 pose 流
	_assert(_pose_count >= 2, "pose received: %d msgs" % _pose_count)

	# 验证 ctrl 消息（W + Space）
	var ctrl_count: int = 0
	if _cap_ctrl.has("key"):
		ctrl_count += 1
	_assert(ctrl_count >= 1, "ctrl sent via EventBus")

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


func _on_pose(pose: Dictionary) -> void:
	_cap_pose = pose
	_pose_count += 1

func _on_voxel(voxels: Array, _is_full: bool) -> void:
	_cap_voxels = voxels

func _on_path(points: Array) -> void:
	_cap_path_points = points

func _on_ctrl(ctrl: Dictionary) -> void:
	_cap_ctrl = ctrl
